"""Run production model helpers without NinjaTrader's protected runtime loader.

Extract exact declarations from the strategy; do not copy model implementations.
Native order callbacks still require separate NinjaTrader runtime validation.
"""
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / 'OvernightBiasRangeBreakoutNT8.cs'
CSC = Path(r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe')

def declaration(source, name, kind='method'):
    pattern = (r'\b(?:internal|private)\s+(?:sealed\s+)?class\s+' + name + r'\b'
               if kind == 'class' else
               r'\b(?:internal|private)\s+static\s+\w+\s+' + name + r'\s*\(')
    found = re.search(pattern, source)
    if not found:
        raise AssertionError('Missing production declaration: ' + name)
    start = source.index('{', found.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[found.start():end]

source = SOURCE.read_text(encoding='utf-8-sig')
methods = ['Bias', 'SignalTime', 'SignalSide', 'TrailLock', 'Quantity',
           'CoveredStop', 'BracketPrice', 'FillRiskCost', 'ExposureAcquire', 'ExposureRelease',
           'Cutoff', 'Observed', 'Nth', 'FutureSpecial']
pieces = [declaration(source, name) for name in methods]
pieces += [declaration(source, name, 'class') for name in ['Candle', 'WilderAdx']]
wrapper = ('using System; using System.Collections.Generic;\n'
           'namespace NinjaTrader.NinjaScript.Strategies {\n'
           'public class OvernightBiasRangeBreakoutNT8 {\n' +
           '\n'.join(pieces) + '\n}}\n')
with tempfile.TemporaryDirectory(prefix='overnight_contract_') as folder:
    work = Path(folder)
    (work / 'Model.cs').write_text(wrapper, encoding='utf-8')
    (work / 'ModelContractTests.cs').write_bytes((HERE / 'ModelContractTests.cs.txt').read_bytes())
    subprocess.run([str(CSC), '/nologo', '/target:library', '/out:Model.dll', 'Model.cs'], cwd=work, check=True)
    subprocess.run([str(CSC), '/nologo', '/out:ModelContractTests.exe', 'ModelContractTests.cs'], cwd=work, check=True)
    subprocess.run([str(work / 'ModelContractTests.exe'), str(work / 'Model.dll')], cwd=work, check=True)
