import asyncio
from facetrack import initialize, scan_face
from incamera import initialize as initialize_incamera
from outcamera import initialize as initialize_outcamera,get_vision as get_incamera_vision
from analyze_and_mask_object import analyze_and_mask_object

async def main_loop(options):

    while True:
        result = await scan_face(options)  # 顔のスキャンを非同期で実行する
        if result is None:
            return
        mp_image, stable_vectors = result
        mp_image = get_incamera_vision()[2]  # 最新の外カメラ映像を取得する
        print(f"Detected stable FaceVectors ({len(stable_vectors)} face(s)): {stable_vectors}")
        target_name, guide_desc, seg_data = analyze_and_mask_object(mp_image, stable_vectors)  # 解析とマスク処理を実行する


async def main():
    # カメラ初期化
    initialize_incamera()
    #initialize_outcamera()  開発機では外部カメラは使用できないため、初期化はコメントアウト
    options = initialize()  # 初期化処理を呼び出す
    await main_loop(options)  # メインループを開始する


if __name__ == "__main__":
    asyncio.run(main())