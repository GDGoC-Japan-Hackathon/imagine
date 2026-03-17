import os
import google.generativeai as genai
from PIL import Image
import json
import re
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import tkinter as tk
from tkinter import filedialog

# ==========================================
# 1. APIキーの設定
# ==========================================
# 環境変数からAPIキーを取得するか、未設定の場合は直接入力を求めます
key = os.environ.get('GEMINI_API_KEY')
if not key:
    print("環境変数 'GEMINI_API_KEY' が見つかりません。")
    key = input("Gemini APIキーを入力してください: ").strip()

if not key:
    raise ValueError("APIキーが入力されませんでした。プログラムを終了します。")

genai.configure(api_key=key)
model = genai.GenerativeModel('gemini-3-flash-preview')

# ==========================================
# 2. 画像の選択 (Windowsのファイルダイアログを使用)
# ==========================================
print("画像選択ダイアログを開いています...")
root = tk.Tk()
root.withdraw() # Tkinterのメインウィンドウ（不要な小さな窓）を非表示にする
root.attributes('-topmost', True) # ダイアログを最前面に表示

file_path = filedialog.askopenfilename(
    title="解析する画像を選択してください",
    filetypes=[("Image files", "*.jpg *.jpeg *.png *.webp *.bmp")]
)

if file_path:
    print(f"選択された画像: {file_path}")
    img = Image.open(file_path)

    # ==========================================
    # 3. 注目位置の入力受け付けと連続座標への変換
    # ==========================================
    print("\n画像内の注目したい位置を数値で指定してください。")
    try:
        pan = float(input("左右方向 (-90～90, 0が中心, マイナスが左, プラスが右): "))
        tilt = float(input("高さ方向 (-50～50, 0が中心, マイナスが下, プラスが上): "))
        
        pan = max(-90.0, min(90.0, pan))
        tilt = max(-50.0, min(50.0, tilt))
    except ValueError:
        print("無効な入力です。中心(0, 0)として扱います。")
        pan, tilt = 0.0, 0.0

    percent_x = (pan + 90) / 180.0 * 100
    percent_y = (50 - tilt) / 100.0 * 100

    norm_x = int(percent_x * 10)
    norm_y = int(percent_y * 10)

    location_desc = f"画像の左端から {percent_x:.1f}%、上端から {percent_y:.1f}% の位置（正規化座標で [y, x] = [{norm_y}, {norm_x}] 付近）"
    print(f"\n指定された位置: {location_desc} を解析します...")

    # ==========================================
    # 4. 画像解析 (指定位置の対象物特定と解説生成)
    # ==========================================
    user_prompt = f'''あなたは優秀で知識豊富なコンシェルジュ（パーソナルアシスタント）です。
    提供された画像を注意深く観察し、指定された位置にある【単一の対象物（1つだけ）】を見つけ出し、ユーザーへ丁寧に説明する魅力的で専門的な解説を作成してください。

    【注目するべき位置】
    {location_desc}

    以下の条件を厳守してください：
    1. 指定された位置から最も近い、あるいはその位置にある「1つの物体のみ」に焦点を当てること。
    2. 優秀なアシスタントのような、丁寧でありながら堅苦しすぎないスマートなトーンで、専門的な知識を交えて説明すること。
    3. 出力は必ず以下の2つのキーを持つJSON形式のみとすること。
    4. JSON以外のテキスト（```json などのMarkdown記法や挨拶など）は一切含めないこと。

    【出力形式】
    {{
      "名前": "対象物の具体的な名称",
      "解説": "こちらに写っておりますのは…から始まるような、丁寧で詳細な解説文"
    }}'''

    response_analysis = model.generate_content([user_prompt, img])
    analysis_text = response_analysis.text
    
    analysis_json_match = re.search(r'\{.*\}', analysis_text, re.DOTALL)
    target_name = "指定位置の対象物"
    
    if analysis_json_match:
        try:
            analysis_data = json.loads(analysis_json_match.group())
            target_name = analysis_data.get("名前", "指定位置の対象物")
            guide_desc = analysis_data.get("解説", "解説を取得できませんでした。")
            
            print("\n" + "="*50)
            print(f"🎯 【検出された対象物】: {target_name}")
            print("="*50)
            print(f"✨ 【アシスタントの解説】\n{guide_desc}\n")
        except json.JSONDecodeError:
            print("画像解析のJSONパースに失敗しました。")
    else:
        print("期待するJSON形式で画像解析結果が得られませんでした。")

    # ==========================================
    # 5. マスク作成 (特定された対象物のセグメンテーション)
    # ==========================================
    print(f"『{target_name}』のセグメンテーションを開始しています...")
    
    seg_prompt = f"""
    Please perform instance segmentation ONLY on the single object identified as '{target_name}' located near {location_desc} in this image.
    If multiple such objects exist, segment ONLY the one closest to the specified point [y={norm_y}, x={norm_x}].
    Provide the following in a structured JSON format:
    1. 'label': '{target_name}'
    2. 'polygon': A list of precise coordinates [y1, x1, y2, x2, ... yN, xN] representing the boundary of the object. Coordinates must be normalized between 0 and 1000.

    Return the result as a valid JSON array containing exactly ONE object. Do not include markdown formatting like ```json.
    """

    response_seg = model.generate_content([seg_prompt, img])
    seg_raw_text = response_seg.text
    seg_json_match = re.search(r'\[\s*\{.*\}\s*\]', seg_raw_text, re.DOTALL)

    # ==========================================
    # 6. マスク付き画像の作成と表示
    # ==========================================
    if seg_json_match:
        try:
            seg_data = json.loads(seg_json_match.group())
            width, height = img.size

            fig, ax = plt.subplots(figsize=(12, 12))
            ax.imshow(img)
            
            color = 'red'

            for i, obj in enumerate(seg_data):
                if i > 0: 
                    break

                if 'polygon' in obj:
                    poly_coords = obj['polygon']
                    pixel_coords = []
                    
                    for j in range(0, len(poly_coords), 2):
                        y = poly_coords[j] * height / 1000
                        x = poly_coords[j+1] * width / 1000
                        pixel_coords.append((x, y))

                    polygon_patch = patches.Polygon(
                        pixel_coords,
                        closed=True,
                        linewidth=3,
                        edgecolor=color,
                        facecolor=color,
                        alpha=0.4
                    )

                    ax.add_patch(polygon_patch)

            plt.axis('off')
            print("\nマスク付き画像を生成しました。表示ウィンドウを閉じるとプログラムが終了します。")
            
            # Windowsで画像ウィンドウを表示し、閉じるまで待機する
            plt.show()

        except json.JSONDecodeError as e:
            print(f"セグメンテーションのJSONパースエラー: {e}")
    else:
        print("有効なセグメンテーションデータが見つかりませんでした。")

else:
    print("画像が選択されませんでした。プログラムを終了します。")