#!/usr/bin/env python3
"""
로컬 Whisper Large-v3-turbo 음성인식 스크립트
Flutter 앱에서 호출하여 사용
"""

import sys
import json
import argparse
from pathlib import Path
import whisper

def transcribe_audio(audio_path, model_name="large-v3-turbo", language="ko"):
    """
    오디오 파일을 Whisper로 음성인식
    
    Args:
        audio_path (str): 오디오 파일 경로
        model_name (str): Whisper 모델명 (large-v3-turbo, large-v3 등)
        language (str): 언어 코드 (ko, en, ja 등)
    
    Returns:
        dict: 음성인식 결과 (JSON 형태)
    """
    try:
        print(f"모델 로드 중: {model_name}")
        model = whisper.load_model(model_name)
        
        print(f"음성인식 시작: {audio_path}")
        result = model.transcribe(
            audio_path,
            language=language,
            task="transcribe",
            verbose=True,
            word_timestamps=True,
            condition_on_previous_text=True,
            temperature=0.0,
            compression_ratio_threshold=2.4,
            logprob_threshold=-1.0,
            no_speech_threshold=0.6,
            initial_prompt=None,
            prepend_punctuations=True,
            append_punctuations=True,
        )
        
        # 결과를 Flutter에서 사용할 수 있는 형태로 변환
        segments = []
        for i, segment in enumerate(result["segments"], 1):
            segments.append({
                "id": i,
                "start": f"{segment['start']:.2f}",
                "end": f"{segment['end']:.2f}",
                "text": segment["text"].strip()
            })
        
        return {
            "success": True,
            "segments": segments,
            "language": result.get("language", language),
            "total_duration": result.get("segments", [{}])[-1].get("end", 0) if result.get("segments") else 0
        }
        
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "segments": []
        }

def main():
    parser = argparse.ArgumentParser(description="로컬 Whisper 음성인식")
    parser.add_argument("audio_path", help="오디오 파일 경로")
    parser.add_argument("--model", default="large-v3-turbo", help="Whisper 모델명")
    parser.add_argument("--language", default="ko", help="언어 코드")
    parser.add_argument("--output", help="출력 JSON 파일 경로 (선택사항)")
    
    args = parser.parse_args()
    
    # 오디오 파일 존재 확인
    if not Path(args.audio_path).exists():
        print(json.dumps({
            "success": False,
            "error": f"오디오 파일을 찾을 수 없습니다: {args.audio_path}",
            "segments": []
        }))
        sys.exit(1)
    
    # 음성인식 실행
    result = transcribe_audio(args.audio_path, args.model, args.language)
    
    # 결과 출력
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"결과가 {args.output}에 저장되었습니다.")
    else:
        print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main() 