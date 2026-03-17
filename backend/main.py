import asyncio
from facetrack import initialize, scan_face

async def main_loop(camera, options):
    while True:
        result = await scan_face(camera, options)  # 顔のスキャンを非同期で実行する
        if result is None:
            return
        else:
            mp_image, stable_vectors = result
            print(f"Detected stable FaceVectors ({len(stable_vectors)} face(s)): {stable_vectors}")


async def main():
    camera, options = initialize()  # 初期化処理を呼び出す
    await main_loop(camera, options)  # メインループを開始する


if __name__ == "__main__":
    asyncio.run(main())