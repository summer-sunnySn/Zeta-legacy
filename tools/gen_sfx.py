#!/usr/bin/env python3
# Procedurally synthesize Zeta Legacy sound effects + ambient music as WAV files.
import wave, struct, math, random, os

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
os.makedirs(OUT, exist_ok=True)

def save(name, samples):
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        buf = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32767)
            buf += struct.pack("<h", v)
        w.writeframes(buf)
    print("wrote", name, len(samples), "samples")

def shoot(f0, f1, dur, vol):
    n = int(SR*dur); out=[]
    for i in range(n):
        t=i/SR; f=f0+(f1-f0)*(i/n)
        s=math.sin(2*math.pi*f*t)
        s=(1 if s>0 else -1)*0.45 + s*0.55          # square-ish bite
        out.append(s*math.exp(-t/(dur*0.4))*vol)
    return out

def explosion(dur, vol):
    n=int(SR*dur); out=[]; lp=0.0
    for i in range(n):
        t=i/SR
        lp=lp*0.65+random.uniform(-1,1)*0.35          # low-passed noise
        boom=math.sin(2*math.pi*(95-55*(i/n))*t)
        out.append((lp*0.75+boom*0.55)*math.exp(-t/(dur*0.34))*vol)
    return out

def hit(dur, vol):
    n=int(SR*dur); out=[]
    for i in range(n):
        t=i/SR
        s=math.sin(2*math.pi*950*t)+random.uniform(-0.5,0.5)
        out.append(s*math.exp(-t/(dur*0.3))*vol*0.5)
    return out

def player_hit(dur, vol):
    n=int(SR*dur); out=[]
    for i in range(n):
        t=i/SR; f=170-90*(i/n)
        s=math.sin(2*math.pi*f*t)+random.uniform(-0.3,0.3)
        out.append(s*math.exp(-t/(dur*0.4))*vol*0.6)
    return out

def rising(dur, vol):
    n=int(SR*dur); out=[]; freqs=[523,659,784,1046]
    seg=n//len(freqs)
    for i in range(n):
        t=i/SR; f=freqs[min(len(freqs)-1,i//seg)]
        e=math.exp(-((i%seg)/SR)/0.09)
        out.append(math.sin(2*math.pi*f*t)*e*vol*0.5)
    return out

def music(dur, vol):
    # All freqs multiples of 1/dur so the buffer loops seamlessly.
    n=int(SR*dur); out=[]
    base=[55.0, 82.5, 110.0, 165.0]   # low A chord, integer cycles over dur
    for i in range(n):
        t=i/SR; s=0.0
        for k,f in enumerate(base):
            lfo=0.5+0.5*math.sin(2*math.pi*(k+1)*t/dur)
            s+=math.sin(2*math.pi*f*t)*lfo
        s+=0.12*math.sin(2*math.pi*440.0*t)*(0.5+0.5*math.sin(2*math.pi*2*t/dur))
        out.append((s/len(base))*vol)
    return out

def pickup(dur, vol):
    n=int(SR*dur); out=[]
    for i in range(n):
        t=i/SR; f=600+1000*(i/n)
        s=math.sin(2*math.pi*f*t)+0.3*math.sin(2*math.pi*f*2*t)
        out.append(s*math.exp(-t/(dur*0.5))*vol*0.5)
    return out

random.seed(7)
save("shoot.wav", shoot(1350, 420, 0.11, 0.38))
save("enemy_shoot.wav", shoot(720, 240, 0.13, 0.30))
save("explosion.wav", explosion(0.7, 0.75))
save("hit.wav", hit(0.07, 0.42))
save("player_hit.wav", player_hit(0.34, 0.7))
save("wave.wav", rising(0.5, 0.4))
save("powerup.wav", pickup(0.4, 0.45))
save("music.wav", music(16.0, 0.22))
print("done")
