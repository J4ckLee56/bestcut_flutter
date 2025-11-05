# 오디오 정렬 파이프라인 (1단계)

WhisperX 강제 정렬을 도입하기 위한 1단계 준비 사항입니다. 현재 단계에서는 Flutter와 통합하지 않고 **명령형 스크립트**로 파이프라인을 검증합니다.

## 준비 사항

- Python 3.10+
- (선택) NVIDIA GPU + CUDA 11.8 – 있으면 속도 향상, 없으면 CPU 모드 사용
- `pip install torch torchaudio whisperx`
- `whisper.cpp` 서브모듈 빌드 및 `ggml-large-v3-turbo.bin` 다운로드 완료
- `ffmpeg` 바이너리 (프로젝트에 포함된 macOS 빌드 또는 환경 변수로 지정)

## 0. 환경 변수

필요 시 아래 변수를 설정해 실행 경로를 재정의할 수 있습니다.

```bash
export FFMPEG_PATH=/absolute/path/to/ffmpeg
export WHISPER_CLI_PATH=/absolute/path/to/whisper-cli
export WHISPER_MODEL_PATH=/absolute/path/to/ggml-large-v3-turbo.bin
```

## 1. 오디오 전처리

```bash
tools/audio_pipeline/preprocess_audio.sh \
  /path/to/input.mov \
  /tmp/cleaned.wav
```

적용되는 필터
- 200Hz 하이패스 / 3kHz 로우패스
- `afftdn` 노이즈 감소
- `loudnorm` 볼륨 정규화
- 모노 16kHz PCM 변환

## 2. Whisper.cpp 인식

```bash
tools/audio_pipeline/run_whisper_cli.sh \
  /tmp/cleaned.wav \
  /tmp/whisper_output
```

생성물
- `/tmp/whisper_output.srt`
- `/tmp/whisper_output.json`
- `/tmp/whisper_output.wts.json` (단어 타임스탬프)

기본 옵션
- `--dtw`, `--word-timestamps`, `--max-len 16`, `--split-on-word`
- 빔 탐색 & 저온도 설정으로 안정성 향상

## 3. WhisperX 강제 정렬

```bash
python tools/audio_pipeline/align_with_whisperx.py \
  --audio /tmp/cleaned.wav \
  --whisper-json /tmp/whisper_output.json \
  --output-json /tmp/aligned.json \
  --output-vtt /tmp/aligned.vtt \
  --device auto \
  --language ko
```

결과 JSON (`aligned.json`)에는 각 세그먼트 내부에 `words` 배열이 포함됩니다.

## 4. 수동 검증 체크리스트

- `aligned.json` 의 `segments[*].words[*]`에 `start`, `end`, `text`가 모두 존재하는지 확인
- SRT, VTT를 재생해보고 실제 발화와 싱크가 맞는지 확인
- 긴 샘플(>30분)에서도 실행 시간을 기록해두기
- CPU 모드(`--device cpu`)와 GPU 모드 모두 시도해 차이를 비교

## 5. 다음 단계

- Flutter `AIService`에서 위 스크립트를 호출/호출 API로 래핑
- `WhisperSegment` 구조체 확장 (`List<WordSegment> words` 등)
- 단어 단위 UI 구현 (파형과 동기화)

---

테스트 후 이상 동작이나 성능 이슈가 있으면 각 단계 출력물을 공유해 주세요. 단계별로 조정하며 안정화한 뒤 Flutter 연동으로 넘어갑니다.

