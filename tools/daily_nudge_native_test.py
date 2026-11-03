"""Run the platform-independent Daily Nudge alarm policy on the JVM."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'apps/client/android/app/src'

def main():
    javac, java = shutil.which('javac'), shutil.which('java')
    if not javac or not java:
        raise SystemExit('A JDK is required for Daily Nudge native policy tests.')
    with tempfile.TemporaryDirectory(prefix='nex-nudge-jvm-') as directory:
        subprocess.run([javac, '-d', directory,
            str(BASE / 'main/java/com/sanyzrn/nex/NexDailyDeliveryPolicy.java'),
            str(BASE / 'test/java/com/sanyzrn/nex/NexDailyDeliveryPolicyTest.java')], check=True)
        subprocess.run([java, '-cp', directory,
            'com.sanyzrn.nex.NexDailyDeliveryPolicyTest'], check=True)

if __name__ == '__main__':
    main()
