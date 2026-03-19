def is_facetrack_successed(angles, lastfacevector):
    return is_gaze_not_moving(angles, lastfacevector)

# 顔の向きと目線の高さが動いていないかを判定する関数
def is_gaze_not_moving(current_angles, previous_angles, yaw_threshold=3.0, pitch_threshold=3.0):
  if current_angles is None or previous_angles is None:
    return False

  delta = current_angles - previous_angles
  return abs(delta.x) <= yaw_threshold and abs(delta.y) <= pitch_threshold