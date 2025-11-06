#!/usr/bin/env python3
"""
오디오 에너지 프로파일 생성 스크립트
FFmpeg astats의 한계를 극복하기 위해 Python으로 직접 오디오 분석
"""

import argparse
import json
import sys
import numpy as np
import wave


def parse_args():
    parser = argparse.ArgumentParser(description="Analyze audio energy profile")
    parser.add_argument("--audio", required=True, help="Path to WAV audio file")
    parser.add_argument("--output-json", required=True, help="Path to write energy profile JSON")
    parser.add_argument("--frame-length", type=float, default=0.1, help="Frame length in seconds (default: 0.1)")
    parser.add_argument("--silence-threshold", type=float, default=-40.0, help="Silence threshold in dB (default: -40)")
    return parser.parse_args()


def rms_to_db(rms):
    """RMS 값을 dB로 변환"""
    if rms == 0:
        return -100.0  # 완전 무음
    return 20 * np.log10(rms)


def analyze_audio_energy(audio_path, frame_length_sec):
    """오디오 파일의 에너지 프로파일 분석"""
    
    # WAV 파일 읽기
    with wave.open(audio_path, 'rb') as wf:
        sample_rate = wf.getframerate()
        n_channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        n_frames = wf.getnframes()
        
        # 전체 오디오 데이터 읽기
        audio_data = wf.readframes(n_frames)
        
    # numpy array로 변환
    if sample_width == 2:  # 16-bit
        audio_array = np.frombuffer(audio_data, dtype=np.int16)
    else:
        raise ValueError(f"Unsupported sample width: {sample_width}")
    
    # 모노로 변환 (필요시)
    if n_channels == 2:
        audio_array = audio_array.reshape(-1, 2).mean(axis=1)
    
    # 정규화 (-1.0 ~ 1.0)
    audio_normalized = audio_array.astype(np.float32) / 32768.0
    
    # 프레임 크기 계산
    frame_size = int(sample_rate * frame_length_sec)
    
    # 프레임별 RMS 계산
    energy_frames = []
    
    for i in range(0, len(audio_normalized), frame_size):
        frame_data = audio_normalized[i:i + frame_size]
        
        if len(frame_data) == 0:
            continue
        
        # RMS 계산
        rms = np.sqrt(np.mean(frame_data ** 2))
        rms_db = rms_to_db(rms)
        
        # 시간 계산
        time_sec = i / sample_rate
        
        energy_frames.append({
            'timeSec': round(float(time_sec), 3),
            'rmsLevel': round(float(rms_db), 2),
        })
    
    return energy_frames


def main():
    args = parse_args()
    
    print(f"🔊 오디오 에너지 분석 시작: {args.audio}")
    print(f"  프레임 길이: {args.frame_length}초")
    print(f"  무음 임계값: {args.silence_threshold}dB")
    
    try:
        energy_frames = analyze_audio_energy(args.audio, args.frame_length)
        
        # JSON으로 저장
        output_data = {
            'audio_file': args.audio,
            'frame_length_sec': args.frame_length,
            'silence_threshold_db': args.silence_threshold,
            'total_frames': len(energy_frames),
            'frames': energy_frames,
        }
        
        with open(args.output_json, 'w', encoding='utf-8') as f:
            json.dump(output_data, f, ensure_ascii=False, indent=2)
        
        print(f"✅ 에너지 프로파일 생성 완료: {len(energy_frames)}개 프레임")
        print(f"  출력 파일: {args.output_json}")
        
        # 통계 출력
        if energy_frames:
            rms_values = [f['rmsLevel'] for f in energy_frames]
            print(f"  RMS 범위: {min(rms_values):.1f}dB ~ {max(rms_values):.1f}dB")
            print(f"  평균 RMS: {np.mean(rms_values):.1f}dB")
            
            # 무음 프레임 비율
            silence_count = sum(1 for rms in rms_values if rms < args.silence_threshold)
            silence_ratio = silence_count / len(rms_values) * 100
            print(f"  무음 프레임: {silence_count}/{len(rms_values)} ({silence_ratio:.1f}%)")
        
    except Exception as e:
        print(f"❌ 오류: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

