import sys,re,statistics as st

def load(f):
    d={}
    for l in open(f):
        m=re.match(r"(.+?)\s{2,}([\d.]+) us",l)
        if m: d.setdefault(m[1].strip(),[]).append(float(m[2]))
    return {k:st.median(v) for k,v in d.items()}
a,b=load(sys.argv[1]),load(sys.argv[2])
rows=[(k,a[k],b[k]) for k in b if k in a and not k.startswith("idle")]
rows.sort(key=lambda r:-abs(r[2]-r[1]))
print(f"{'case':38}{'before':>9}{'now':>9}{'Δ µs':>8}{'Δ %':>7}")
for k,x,y in rows: print(f"{k:38}{x:9.2f}{y:9.2f}{y-x:+8.2f}{(y-x)/x*100:+7.1f}")
