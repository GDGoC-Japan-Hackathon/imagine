def is_facetrack_successed(angles, lastfacevector):
    # 顔のスキャンが成功したかどうかを判定するロジックをここに実装する
    # 例えば、顔の特徴点が一定数以上検出された場合など
    result = True
    if result:
        result = is_gaze_not_moving(angles, lastfacevector)
    return result

# 顔の向きと目線の高さが動いていないかを判定する関数
def is_gaze_not_moving(current_angles, previous_angles, ratio_threshold=8):
  if current_angles is None or previous_angles is None:
    return False

  delta = current_angles - previous_angles
  if delta.x == 0 or delta.y == 0:
   return True

  return abs(delta.x / delta.y) <= ratio_threshold