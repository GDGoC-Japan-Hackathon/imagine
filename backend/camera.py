import time

import cv2 as cv


class Camera:
    """カメラの開閉・フレーム取得を管理するクラス。
    使用例：with 文（コンテキストマネージャ）での使用
        with Camera() as cam:
            ok, frame = cam.read_frame()
    """

    def __init__(self, camera_index: int = 0):
        self.capture = self._open(camera_index)
        if self.capture is None:
            raise RuntimeError("Webカメラを開始できませんでした。")

    # カメラを開く（内部ヘルパー）
    def _open(self, camera_index: int):
        for backend in (cv.CAP_DSHOW, cv.CAP_MSMF, cv.CAP_ANY):
            capture = cv.VideoCapture(camera_index, backend)
            if capture.isOpened():
                return capture
            capture.release()
        return None

    # カメラからフレームを読み取る
    def read_frame(self, retries: int = 30, delay_seconds: float = 0.05):
        for _ in range(retries):
            success, frame_bgr = self.capture.read()
            if success and frame_bgr is not None:
                return True, frame_bgr
            time.sleep(delay_seconds)
        return False, None

    # 終了処理
    def release(self):
        if self.capture and self.capture.isOpened():
            self.capture.release()

    # with 文サポート
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.release()
        return False