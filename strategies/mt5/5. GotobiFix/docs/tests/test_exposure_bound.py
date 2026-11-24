"""Gotobi: exposure must be bounded by the flat-entry rule and fixed Lots, not by a cap input.

Two structural claims and one behavioural claim:
  * no MaxExposureLots input, no gfExposureCap runtime state (the cap could never fire);
  * GfEntries refuses to enter while any owned position is open, so exposure is one leg of Lots.
No account, terminal or order calls.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root
    main_src = (root / 'GotobiFix.mq5').read_text(encoding='utf-8-sig')
    runtime = (root / 'ExecutionRuntime.mqh').read_text(encoding='utf-8-sig')

    start = runtime.index('   if(leg==1 && gfOwnedN>0)')
    end = runtime.index('\n', runtime.index('   if(leg==0 && gfOwnedN>0)')) + 1
    block = runtime[start:end]

    code = r'''
using System;
class BoundChecks {
 static int gfOwnedN; static string gfNote=""; static bool reached;
 static void Print(string t){}
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);}
 static void Guard(int leg){BLOCK reached=true;}
 static void FlatLongProceeds(){gfOwnedN=0;gfNote="";reached=false;Guard(0);Check(reached,"flat long entry blocked");}
 static void FlatShortProceeds(){gfOwnedN=0;gfNote="";reached=false;Guard(1);Check(reached,"flat short entry blocked");}
 static void LongBlockedWhileOwned(){gfOwnedN=1;gfNote="";reached=false;Guard(0);Check(!reached,"long entry while positioned");Check(gfNote.Contains("already open"),"missing owned-exposure note, got: "+gfNote);}
 static void ShortBlockedWhileOwned(){gfOwnedN=1;gfNote="";reached=false;Guard(1);Check(!reached,"short entry while positioned");Check(gfNote.Contains("waiting for long"),"missing wait note, got: "+gfNote);}
 static int Main(){Action[] tests={FlatLongProceeds,FlatShortProceeds,LongBlockedWhileOwned,ShortBlockedWhileOwned};int failed=0;
 foreach(var test in tests){try{test();Console.WriteLine("PASS "+test.Method.Name);}catch(Exception e){failed++;Console.WriteLine("FAIL "+test.Method.Name+": "+e.Message);}}
 Console.WriteLine((tests.Length-failed)+"/"+tests.Length+" exposure bound checks passed");return failed==0?0:1;}
}
'''.replace('BLOCK', block)

    with tempfile.TemporaryDirectory(prefix='gf-bound-', dir='C:/Users/ADMINI~1/AppData/Local/Temp') as directory:
        source, binary = Path(directory) / 'BoundChecks.cs', Path(directory) / 'BoundChecks.exe'
        source.write_text(code, encoding='utf-8')
        built = subprocess.run(['C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe', '/nologo',
                                f'/out:{binary}', str(source)], capture_output=True, text=True)
        if built.returncode:
            print(built.stdout + built.stderr)
            return built.returncode
        ran = subprocess.run([str(binary)], capture_output=True, text=True)
        print(ran.stdout + ran.stderr, end='')

    structural = 0
    if 'MaxExposureLots' not in main_src:
        print('PASS NoExposureCapInput'); structural += 1
    else:
        print('FAIL NoExposureCapInput: MaxExposureLots input still declared')
    if 'gfExposureCap' not in runtime:
        print('PASS NoCapRuntimeState'); structural += 1
    else:
        print('FAIL NoCapRuntimeState: gfExposureCap still referenced')

    total = 4 + 2
    passed = (4 if ran.returncode == 0 else 0) + structural
    print(f'{passed}/{total} exposure bound checks passed')
    return 0 if (ran.returncode == 0 and structural == 2) else 1


if __name__ == '__main__':
    raise SystemExit(main())
