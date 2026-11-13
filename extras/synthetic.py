import random

def lerp(a:float,b:float,d:float) -> float:
    ((b-a)*d)+a

def format_packet(temp: float) -> str:
    return f"[TEMP={temp:0>6.2f} C]"

def mutated_packet(temp: float) -> str:
    offset = random.randint(0,4)
    return f"{format_packet(temp)}{format_packet(temp)}"[offset:-random.randint(0,4)]

for _ in range(100):
    vl = random.randint(-100,200)
    print(mutated_packet(vl))
