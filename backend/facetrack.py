import json
import math
import os
import time

os.environ["GLOG_minloglevel"] = "2"
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"

import cv2 as cv
import mediapipe as mp
from mediapipe.tasks.python import vision


MODEL_PATH = "model/face_landmarker.task"
PITCH_NEUTRAL_THRESHOLD_DEG = 5.0

# カメラを開く関数
def open_camera(camera_index=0):
  for backend in (cv.CAP_DSHOW, cv.CAP_MSMF, cv.CAP_ANY):
    capture = cv.VideoCapture(camera_index, backend)
    if capture.isOpened():
      return capture
    capture.release()
  return None

# カメラからフレームを読み取る関数
def read_frame(capture, retries=30, delay_seconds=0.05):
  for _ in range(retries):
    success, frame_bgr = capture.read()
    if success and frame_bgr is not None:
      return True, frame_bgr
    time.sleep(delay_seconds)
  return False, None

# 結果から表示用のテキスト行を構築する関数
def build_result_lines(result, angles=None):
  face_count = len(result.face_landmarks)
  lines = [f"Faces: {face_count}"]

  if face_count == 0:
    lines.append("No face detected")
    return lines

  first_face = result.face_landmarks[0]
  lines.append(f"Landmarks: {len(first_face)}")

  if len(first_face) > 1:
    key_point = first_face[1]
    lines.append(f"Point[1]: x={key_point.x:.3f} y={key_point.y:.3f}")

  if result.face_blendshapes:
    top_blendshape = max(result.face_blendshapes[0], key=lambda item: item.score)
    lines.append(f"Blendshape: {top_blendshape.category_name} {top_blendshape.score:.2f}")

  if angles:
    data = json.loads(angles)
    lines.append(f"Yaw:   {data['yaw']}°")
    lines.append(f"Pitch: {data['pitch']}°")
    lines.append(f"YawVector:  {data['yaw']}°")
    lines.append(f"Pitch zone: {data['pitch_zone']}")

  lines.append("Press 'q' to quit")
  return lines

def get_angle(landResult):
  # detection_result は FaceLandmarker の出力結果
    if hasattr(landResult, 'facial_transformation_matrixes') and landResult.facial_transformation_matrixes:
        for matrix_data in landResult.facial_transformation_matrixes:
            # matrix_data は numpy の 4x4 行列
            m = matrix_data

            # 変換行列から回転成分(3x3)を抽出
            r11, r12, r13 = m[0][0], m[0][1], m[0][2]
            r21, r22, r23 = m[1][0], m[1][1], m[1][2]
            r31, r32, r33 = m[2][0], m[2][1], m[2][2]

            # オイラー角（角度）の計算 (ラジアン)
            # 左右の首振り (Yaw)
            yaw = math.asin(-r31)

            # 上下の傾き (Pitch)
            pitch = math.atan2(r32, r33)

            # 左右の傾き (Roll)
            roll = math.atan2(r21, r11)

            # ラジアンを度数法(degree)に変換
            yaw_deg = max(-90.0, min(90.0, math.degrees(yaw)))
            pitch_deg = math.degrees(pitch) * -1
            roll_deg = math.degrees(roll)

            if pitch_deg <= -PITCH_NEUTRAL_THRESHOLD_DEG:
              pitch_zone = -1
            elif pitch_deg >= PITCH_NEUTRAL_THRESHOLD_DEG:
              pitch_zone = 1
            else:
              pitch_zone = 0

            # JSON で返す
            result = {
              "yaw": round(yaw_deg, 2),
              "pitch": round(pitch_deg, 2),
              "roll": round(roll_deg, 2),
              "pitch_zone": pitch_zone,
            }
            return json.dumps(result)
    return None
  

# 結果をフレームにオーバーレイ表示する関数
def draw_result_overlay(frame_bgr, result):
  overlay = frame_bgr.copy()
  angles = get_angle(result)
  lines = build_result_lines(result, angles)

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

# メインループ
def main():
  base_options = mp.tasks.BaseOptions(model_asset_path=MODEL_PATH)
  options = vision.FaceLandmarkerOptions(
    base_options=base_options,
    running_mode=vision.RunningMode.VIDEO,
    num_faces=1,
    output_facial_transformation_matrixes=True,
  )

  capture = open_camera(0)
  if capture is None:
    raise RuntimeError("Webカメラを開始できませんでした。")
  with vision.FaceLandmarker.create_from_options(options) as landmarker:
    while True:
      success, frame_bgr = read_frame(capture)
      if not success:
        print("カメラからフレームを取得できませんでした。")
        break

      frame_rgb = cv.cvtColor(frame_bgr, cv.COLOR_BGR2RGB)
      mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)

      timestamp_ms = int(time.time() * 1000)
      landResult = landmarker.detect_for_video(mp_image, timestamp_ms)
      display_frame = draw_result_overlay(frame_bgr, landResult)
      cv.imshow("Webcam", display_frame)
      # "q"キーで終了
      if cv.waitKey(1) & 0xFF == ord("q"):
        break
  # 終了処理
  capture.release()
  cv.destroyAllWindows()


if __name__ == "__main__":
  main()