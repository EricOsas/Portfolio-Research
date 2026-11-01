# Local NCD minute-file inspection helper.
# Format decoder adapted from tbraman-dev/ninjatrader-to-parquet (MIT License),
# with format logic credited to JR Stokka's NinjaTraderNCDFiles (MIT).
import re, struct
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
EPOCH_TICKS = 621355968000000000
TICKS_PER_MIN = 600_000_000
HOUR_US = 3_600_000_000
EPOCH = datetime(1970, 1, 1)
MIN_VOL = {1:(1,1),2:(1,100),3:(1,500),4:(1,1000),5:(2,1),6:(4,1),7:(8,1)}
HLC_SZ = (0,1,2,4)

def to_utc_us(local_ticks, tz="America/New_York"):
    tz = ZoneInfo(tz)
    us = (np.asarray(local_ticks,dtype=np.int64)-EPOCH_TICKS)//10
    hrs, inv = np.unique(us//HOUR_US, return_inverse=True)
    off=[]
    for h in hrs:
        local=(EPOCH+timedelta(hours=int(h))).replace(fold=1,tzinfo=tz)
        off.append(int(local.utcoffset()/timedelta(microseconds=1)))
    off=np.asarray(off,dtype=np.int64)
    return us-off[inv].reshape(us.shape)

def decode_minute(path, tz="America/New_York"):
    path=Path(path); name=path.name
    if not re.fullmatch(r"\d{8}\.Last\.ncd|\d{8}\.Bid\.ncd|\d{8}\.Ask\.ncd",name):
        raise ValueError(f"not a daily minute NCD file: {name}")
    buf=path.read_bytes()
    if len(buf)<28: raise ValueError("short header")
    ver,tick,first,t=struct.unpack_from("<iddq",buf,0)
    if ver!=1: raise ValueError(f"unsupported NCD version {ver}")
    p=round(first/tick); n=len(buf); i=28
    T=[]; O=[]; H=[]; L=[]; C=[]; V=[]
    while i<n:
        if i+2>n: raise ValueError(f"truncated record at {i}")
        b1=buf[i]; b2=buf[i+1]; j=i+2
        tc=b1&3
        if tc==0: t+=TICKS_PER_MIN
        elif tc==1: t+=buf[j]*TICKS_PER_MIN; j+=1
        elif tc==2: t+=(buf[j]<<8|buf[j+1])*TICKS_PER_MIN; j+=2
        elif tc==3: t+=int.from_bytes(buf[j:j+4],"big"); j+=4
        else: raise ValueError(f"unsupported minute time code {tc} at {i}")
        oc=(b1>>2)&3
        if oc==1: p+=buf[j]-0x80; j+=1
        elif oc==2: p+=(buf[j]<<8|buf[j+1])-0x8000; j+=2
        elif oc==3: p+=int.from_bytes(buf[j:j+4],"big")-0x40000000; j+=4
        if b2&0x0C: raise ValueError(f"unsupported minute flags {b2:#x} at {i}")
        sz=HLC_SZ[(b2>>4)&3]; hi=p+int.from_bytes(buf[j:j+sz],"big"); j+=sz
        sz=HLC_SZ[b2>>6]; lo=p-int.from_bytes(buf[j:j+sz],"big"); j+=sz
        sz=HLC_SZ[b2&3]; cl=lo+int.from_bytes(buf[j:j+sz],"big"); j+=sz
        vc=MIN_VOL.get(b1>>5)
        if vc is None: raise ValueError(f"unsupported volume code {b1>>5} at {i}")
        sz,mul=vc; v=int.from_bytes(buf[j:j+sz],"big")*mul; j+=sz
        if j>n: raise ValueError(f"record exceeds file at {i}")
        T.append(t); O.append(p); H.append(hi); L.append(lo); C.append(cl); V.append(v)
        i=j
    nd=max(0,-__import__('decimal').Decimal(str(tick)).as_tuple().exponent)
    utc=to_utc_us(T,tz)
    return {"utc_us":utc,"open":np.round(np.asarray(O)*tick,nd),"high":np.round(np.asarray(H)*tick,nd),
            "low":np.round(np.asarray(L)*tick,nd),"close":np.round(np.asarray(C)*tick,nd),"volume":np.asarray(V,dtype=np.int64),
            "tick_size":tick,"rows":len(T)}

if __name__=="__main__":
    import sys
    d=decode_minute(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else "America/New_York")
    from datetime import timezone
    print("rows",d["rows"],"tick_size",d["tick_size"],"volume",int(d["volume"].sum()))
    print("first_utc",datetime.fromtimestamp(int(d["utc_us"][0])/1e6,timezone.utc),"last_utc",datetime.fromtimestamp(int(d["utc_us"][-1])/1e6,timezone.utc))
    for i in range(min(5,d["rows"])):
        print(i, int(d["utc_us"][i]), d["open"][i],d["high"][i],d["low"][i],d["close"][i],int(d["volume"][i]))
