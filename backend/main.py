import asyncio
from facetrack import FaceVector, open_camera, read_frame, build_result_lines,initialize,scan_face

async def main_loop(capture, options):
    while True:
        result = await scan_face(capture, options)  # 顔のスキャンを非同期で実行する
        if result is None:
            return
        else:
            print(f"Detected FaceVector: {result}")
            

async def main():
    capture, options = initialize()  # 初期化処理を呼び出す
    await main_loop(capture, options)  # メインループを開始する


if __name__ == "__main__":
    asyncio.run(main())