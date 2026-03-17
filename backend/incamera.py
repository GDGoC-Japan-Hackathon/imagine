import cv2 as cv
import mediapipe as mp
from camera import Camera

global camera

# 初期化処理
def initialize():
  global camera
  print("Initializing InCamera...")

  camera = Camera(0)
  print("InCamera initialized.")
  return camera

# カメラ映像を取得する
def get_vision():
    success, frame_bgr = camera.read_frame()
    if not success:
        print("カメラからフレームを取得できませんでした。")
        return
    frame_rgb = cv.cvtColor(frame_bgr, cv.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
    return success, frame_bgr, mp_image

# カメラを解放する
def release_camera():
    if camera:
        camera.release()