"""Authored foliage with solid silhouettes: no alpha-card loss at the gameplay camera."""
from pathlib import Path
source = Path(__file__).with_name('build_models.py')
exec(compile(source.read_text(encoding='utf-8').split("for kind in ['player','patrol','charger','repair']:")[0], str(source), 'exec'))
foliage = [mat('Garden foliage '+str(i), c, 0, .92) for i,c in enumerate(['405638','506743','60774B','71814D'])]
clear();random.seed(420)
rod('Tapered trunk',(0,0,0),(.07,0,3.8),.13,TRUNK)
for i in range(11):
    a=i*math.tau/11
    end=Vector((math.cos(a)*1.45, math.sin(a)*1.45, 3.25+random.random()*.7))
    rod('Branch',(.06,0,1.65),end,.065,TRUNK)
    for j in range(10):
        p=end+Vector((random.uniform(-.48,.48),random.uniform(-.48,.48),random.uniform(-.3,.55)))
        sz=random.uniform(.27,.53)
        o=sphere('Rounded foliage',p,(sz*1.25,sz,sz*.87),random.choice(foliage),2)
        for f in o.data.polygons:f.use_smooth=True
for i in range(24):
    p=(random.uniform(-.9,.9),random.uniform(-.9,.9),random.uniform(3.5,4.5))
    sphere('Upper canopy',p,(.42,.38,.4),random.choice(foliage),2)
export('garden_oak')
clear();random.seed(421)
for i in range(14):
    p=(random.uniform(-.55,.55),random.uniform(-.4,.4),random.uniform(.18,.4))
    o=sphere('Hedge leaves',p,(.36,.3,.32),random.choice(foliage),2)
    for f in o.data.polygons:f.use_smooth=True
export('garden_hedge')
print('GARDEN_FOLIAGE_READY',flush=True)
