#!/usr/bin/env python3
"""Collect public video evidence without invoking Pi or an inference provider.

Raw captions and media stay outside the checkout. This never marks a video reviewed.
Run with --ids for a bounded batch; run --frames after choosing relevant timestamps.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def command(args, timeout=90):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=True).stdout


def video_info(video_id, folder):
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / 'info.json'
    if not path.exists() or path.stat().st_mtime < time.time() - 3600:
        path.write_text(command(['yt-dlp', '--skip-download', '--no-warnings',
                                 '--socket-timeout', '15', '--retries', '1',
                                 '--dump-single-json', f'https://www.youtube.com/watch?v={video_id}']))
    return json.loads(path.read_text())


def collect(video, output):
    folder = output / video['id']
    folder.mkdir(parents=True, exist_ok=True)
    result = {'id': video['id'], 'url': video['url'], 'reviewed': False}
    try:
        info = video_info(video['id'], folder)
        result.update({k: info.get(k) for k in ['title', 'channel', 'duration']})
        caption_path = folder / 'captions.json3'
        caption_source = folder / 'caption-source.json'
        manual = info.get('subtitles', {})
        automatic = info.get('automatic_captions', {})
        choices = [(kind, lang, track) for kind, tracks in [('manual', manual), ('automatic', automatic)]
                   for lang in (['en', 'en-orig'] if kind == 'manual' else ['en-orig', 'en'])
                   for track in tracks.get(lang, [])
                   if track.get('ext') == 'json3']
        if not choices:
            result['caption_error'] = 'No English caption track exposed by yt-dlp'
        else:
            kind, lang, track = choices[0]
            if caption_path.exists():
                try:
                    json.loads(caption_path.read_bytes())
                except (ValueError, OSError):
                    caption_path.unlink(missing_ok=True)
            if not caption_path.exists():
                # macOS curl uses the system trust store; do not disable TLS checks.
                pending_path = folder / 'captions.pending.json3'
                try:
                    command(['curl', '--fail', '--silent', '--show-error', '--max-time', '35',
                             '--output', str(pending_path), track['url']], timeout=40)
                    json.loads(pending_path.read_bytes())
                    pending_path.replace(caption_path)
                finally:
                    pending_path.unlink(missing_ok=True)
                caption_source.write_text(json.dumps({'kind': kind, 'language': lang}) + '\n')
            provenance = (json.loads(caption_source.read_text()) if caption_source.exists()
                          else {'kind': kind, 'language': 'cached-English-track'})
            captions = json.loads(caption_path.read_text())
            lines = []
            end_ms = 0
            for event in captions.get('events', []):
                text = ''.join(s.get('utf8', '') for s in event.get('segs', [])).strip()
                if not text:
                    continue
                ms = event.get('tStartMs', 0)
                end_ms = max(end_ms, ms + event.get('dDurationMs', 0))
                seconds = int(ms / 1000)
                lines.append(f'[{seconds // 60:02d}:{seconds % 60:02d}] {text}')
            transcript = folder / 'transcript.txt'
            transcript.write_text('\n'.join(lines) + '\n')
            result.update(caption_kind=provenance['kind'], caption_language=provenance['language'], caption_events=len(lines),
                          caption_end_seconds=end_ms / 1000, transcript=str(transcript),
                          transcript_sha256=hashlib.sha256(transcript.read_bytes()).hexdigest())
    except (subprocess.SubprocessError, OSError, ValueError) as error:
        # Do not write signed stream/caption URLs or request headers to the evidence log.
        result['access_error'] = type(error).__name__
        if isinstance(error, subprocess.CalledProcessError):
            result['exit_code'] = error.returncode
    (folder / 'evidence.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)
    return result


def frames(video_id, times, output):
    folder = output / video_id
    info = video_info(video_id, folder)
    # Extract the same frames-only path Pi uses. No Gemini fallback.
    formats = [f for f in info.get('formats', [])
               if f.get('vcodec') != 'none' and f.get('ext') == 'mp4'
               and f.get('protocol') in ['https', 'http'] and f.get('height', 9999) <= 480]
    if not formats:
        raise ValueError('No direct small video stream exposed')
    stream = max(formats, key=lambda f: f.get('height', 0))['url']
    for seconds in times:
        target = folder / f'frame-{seconds:05d}.jpg'
        if not target.exists():
            try:
                command(['ffmpeg', '-v', 'error', '-ss', str(seconds), '-i', stream,
                         '-frames:v', '1', '-vf', 'scale=960:-1', '-y', str(target)], timeout=45)
            except subprocess.SubprocessError as error:
                raise SystemExit(f'Frame extraction failed at {seconds}s: {type(error).__name__}') from None
        print(target, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ids', nargs='+')
    parser.add_argument('--frames', nargs='+', type=int)
    options = parser.parse_args()
    options.output = options.output.resolve()
    if options.output.is_relative_to(ROOT):
        parser.error('Raw research evidence must stay outside the checkout')
    manifest = json.loads((ROOT / 'docs/product-program/research-manifest.json').read_text())
    videos = [v for v in manifest['videos'] if not options.ids or v['id'] in options.ids]
    if options.ids and set(options.ids) - {v['id'] for v in videos}:
        parser.error('Unknown video ID')
    if options.frames:
        if len(videos) != 1:
            parser.error('--frames requires exactly one video ID')
        frames(videos[0]['id'], options.frames, options.output)
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda v: collect(v, options.output), videos))


if __name__ == '__main__':
    main()
