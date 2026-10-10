#!/usr/bin/env python3
"""Exercise the real ReceiverEngine with independent FFmpeg publishers on loopback."""
import json, os, pathlib, shutil, socket, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
FFMPEG = shutil.which('ffmpeg'); FFPROBE = shutil.which('ffprobe')
assert FFMPEG and FFPROBE, 'Install FFmpeg first'
TEMP = pathlib.Path(tempfile.mkdtemp(prefix='framerelay-test-'))

def wait_for(predicate, seconds=25):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            value = predicate()
            if value: return value
        except (OSError, ValueError): pass
        time.sleep(.1)
    raise AssertionError('Timed out waiting for test state')

def test(record, audio, takes):
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]
    folder = TEMP / f'{record}-{audio}'; folder.mkdir()
    cfg = dict(cameraName='Synthetic test', mode='RTMP listener', address='127.0.0.1', port=port,
               streamPath='live/test', rtspURL='', recordClips=record, includeAudio=audio,
               mirrorPreview=False, autoReconnect=True, startAtLogin=False, autoStartReceiver=False,
               recordingFolder=str(folder / 'clips'), ffmpegPath=FFMPEG, minimumFreeGB=1)
    config = folder/'config.json'; config.write_text(json.dumps(cfg))
    status = folder/'status.json'; stop = folder/'stop'
    def state(): return json.loads(status.read_text())
    receiver = subprocess.Popen([str(ROOT/'build/EngineHarness'), str(config), str(status), str(stop)], stdout=subprocess.DEVNULL, stderr=open(folder/'receiver.log','w'))
    try:
        for take in range(takes):
            wait_for(lambda: state()['state'] == 'Listening')
            time.sleep(.4)
            publisher = subprocess.Popen([FFMPEG, '-hide_banner', '-loglevel', 'error', '-re', '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '4', '-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-f', 'flv', f'rtmp://127.0.0.1:{port}/live/test'], stdout=subprocess.DEVNULL, stderr=open(folder/f'publisher-{take}.log','w'))
            try:
                wait_for(lambda: state()['state'] == 'Live' and state()['frames'] > 1)
                assert state()['recording'] == record
                publisher.wait(timeout=20); assert publisher.returncode == 0
            finally:
                if publisher.poll() is None: publisher.kill(); publisher.wait()
            if record: wait_for(lambda: len(list((folder/'clips').glob('*.mp4'))) == take+1)
            wait_for(lambda: state()['state'] == 'Listening')
        stop.touch(); receiver.wait(timeout=20); assert receiver.returncode == 0
        if not record:
            assert not (folder/'clips').exists(), 'Preview-only mode wrote media'
        else:
            for clip in (folder/'clips').glob('*.mp4'):
                metadata = json.loads(subprocess.check_output([FFPROBE, '-v','error','-show_streams','-show_format','-of','json', str(clip)]))
                video = next(s for s in metadata['streams'] if s['codec_type']=='video')
                assert (video['width'],video['height'],video['r_frame_rate']) == (1920,1080,'25/1')
                assert any(s['codec_type']=='audio' for s in metadata['streams']) == audio
                assert 3.5 < float(metadata['format']['duration']) < 5
                subprocess.run([FFMPEG,'-v','error','-i',str(clip),'-f','null','-'],check=True,timeout=20)
            assert not list((folder/'clips').glob('*.mkv'))
        print(f'PASS recording={record}, audio={audio}, takes={takes}', flush=True)
    finally:
        if receiver.poll() is None:
            stop.touch()
            try: receiver.wait(timeout=15)
            except subprocess.TimeoutExpired: receiver.kill(); receiver.wait()

try:
    test(True, True, 2)
    test(True, False, 1)
    test(False, True, 1)
    print(f'All engine integration checks passed. Private test files: {TEMP}')
except Exception:
    print(f'Test failed; inspect private artifacts: {TEMP}')
    raise
