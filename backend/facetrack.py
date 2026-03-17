import asyncio
import math
import time

import cv2 as cv
import mediapipe as mp
from mediapipe.tasks.python import vision
from facetrackAnalyzer import is_facetrack_successed
from incamera import get_vision,release_camera

MODEL_PATH = "model/face_landmarker.task"
NEXT_CHECK_INTERVAL_MS = 2000

# 顔認識のベクトルクラス
class FaceVector:
  def __init__(self, x, y):
    self.x = x # 顔の向き
    self.y = y # 目線の高さ

  def __sub__(self, other):
    if not isinstance(other, FaceVector):
      return NotImplemented
    return FaceVector(self.x - other.x, self.y - other.y)

  def __repr__(self):
    return f"({self.x}, {self.y})"

# 結果から表示用のテキスト行を構築する関数
def build_result_lines(result, angles_list=None):
  face_count = len(result.face_landmarks)
  lines = [f"Faces: {face_count}"]

  if face_count == 0:
    lines.append("No face detected")
    lines.append("Press 'q' to quit")
    return lines

  for i, face in enumerate(result.face_landmarks):
    lines.append(f"Face {i}: Landmarks: {len(face)}")
    if len(face) > 1:
      key_point = face[1]
      lines.append(f"  Point[1]: x={key_point.x:.3f} y={key_point.y:.3f}")
    if result.face_blendshapes and i < len(result.face_blendshapes):
      top_blendshape = max(result.face_blendshapes[i], key=lambda item: item.score)
      lines.append(f"  Blendshape: {top_blendshape.category_name} {top_blendshape.score:.2f}")
    if angles_list and i < len(angles_list):
      lines.append(f"  FaceVector: {angles_list[i]}")

  lines.append("Press 'q' to quit")
  return lines

def get_angle(landResult):
  # 全顔分の FaceVector をリストで返す
  vectors = []
  if hasattr(landResult, 'facial_transformation_matrixes') and landResult.facial_transformation_matrixes:
    for matrix_data in landResult.facial_transformation_matrixes:
      m = matrix_data
      r31, r32, r33 = m[2][0], m[2][1], m[2][2]
      yaw = math.asin(-r31)
      pitch = math.atan2(r32, r33)
      yaw_deg = max(-90.0, min(90.0, math.degrees(yaw)))
      pitch_deg = math.degrees(pitch) * -1
      vectors.append(FaceVector(round(yaw_deg, 2), round(pitch_deg, 2)))
  return vectors
  

# 結果をフレームにオーバーレイ表示する関数
def draw_result_overlay(frame_bgr, result, angles_list):
  overlay = frame_bgr.copy()
  lines = build_result_lines(result, angles_list)

  panel_height = 30 + len(lines) * 28
  cv.rectangle(overlay, (10, 10), (430, panel_height), (0, 0, 0), -1)
  blended = cv.addWeighted(overlay, 0.45, frame_bgr, 0.55, 0)

  for index, line in enumerate(lines):
    y = 35 + index * 28
    cv.putText(
      blended,
      line,
      (20, y),
      cv.FONT_HERSHEY_SIMPLEX,
      0.7,
      (255, 255, 255),
      2,
      cv.LINE_AA,
    )

  return blended

# 次の顔認識チェックのタイムスタンプをリセットする関数
def reset_nextcheck():
  return  int(time.time() * 1000 + NEXT_CHECK_INTERVAL_MS)

# 目線が動いていない状態を取得する関数（複数顔対応）
def get_GazeNotMoving(mp_image, face_vectors, face_successes):
  if not face_vectors:
    print("顔が検出されていません")
    return None
  stable_vectors = []
  for fv, success in zip(face_vectors, face_successes):
    if fv is not None:
      if success:
        print(f"目線が動いていません: {fv}")
        stable_vectors.append(fv)
      else:
        print(f"目線が動いています: {fv}")
  if stable_vectors:
    return mp_image, stable_vectors
  return None

# 初期化処理
def initialize():
  print("Initializing Face Tracker...")
  base_options = mp.tasks.BaseOptions(model_asset_path=MODEL_PATH)
  options = vision.FaceLandmarkerOptions(
    base_options=base_options,
    running_mode=vision.RunningMode.VIDEO,
    num_faces=5,
    output_facial_transformation_matrixes=True,
  )

  print("Face Tracker initialized.")
  return options

async def scan_face(options):
  with vision.FaceLandmarker.create_from_options(options) as landmarker:
    last_face_vectors = {}   # face_index -> FaceVector
    face_successes = {}      # face_index -> bool
    nexttimestamp_ms = reset_nextcheck()

    while True:
      success, frame_bgr,mp_image = get_vision()
      if not success:
        break
      timestamp_ms = int(time.time() * 1000)
      landResult = landmarker.detect_for_video(mp_image, timestamp_ms)
      angles_list = get_angle(landResult)
      display_frame = draw_result_overlay(frame_bgr, landResult, angles_list)
      cv.imshow("Webcam", display_frame)
      # 各顔のベクトルを更新する
      for i, angles in enumerate(angles_list):
        prev = last_face_vectors.get(i)
        if is_facetrack_successed(angles, prev):
          face_successes[i] = True
        else:
          print(f"顔{i}の目線が動いています")
          face_successes[i] = False
          nexttimestamp_ms = reset_nextcheck()
        last_face_vectors[i] = angles
      # フレームから消えた顔のステートを削除する
      for i in list(last_face_vectors.keys()):
        if i >= len(angles_list):
          del last_face_vectors[i]
          face_successes.pop(i, None)
      # 一定時間経過したら全顔の安定状態をチェックする
      if(timestamp_ms >= nexttimestamp_ms):
        current_vectors = [last_face_vectors.get(i) for i in range(len(angles_list))]
        current_successes = [face_successes.get(i, False) for i in range(len(angles_list))]
        print(f"FaceVectors: {current_vectors}")
        currentGaze = get_GazeNotMoving(mp_image, current_vectors, current_successes)
        # 全員の目線が安定していれば返す
        if currentGaze is not None:
          print("目線が動いていない状態を検出しました。")
          return currentGaze

        nexttimestamp_ms = reset_nextcheck()
        
      # "q"キーで終了
      if cv.waitKey(1) & 0xFF == ord("q"):
        break
      await asyncio.sleep(0.1)  # 非同期で少し待機してUIを更新
  # 終了処理
  release_camera()
  cv.destroyAllWindows()
  return None