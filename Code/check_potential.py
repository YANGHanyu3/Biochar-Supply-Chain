import pandas as pd

FEEDSTOCKS = {
    'Corn_Stover': dict(mc=17.5, y300=0.38),
    'Soybean_Straw': dict(mc=14.0, y300=0.36),
    'Wheat_Straw': dict(mc=12.5, y300=0.35),
    'Oats_Straw': dict(mc=13.0, y300=0.34),
    'Barley_Straw': dict(mc=12.0, y300=0.34),
    'Switchgrass': dict(mc=12.5, y300=0.38),
    'Miscanthus': dict(mc=15.0, y300=0.37),
    'Poplar': dict(mc=45.0, y300=0.35),
    'Willow': dict(mc=45.0, y300=0.35),
    'Logging_Residues': dict(mc=42.5, y300=0.33),
    'SmallDiameter_Trees': dict(mc=45.0, y300=0.33),
    'Mill_Residues': dict(mc=35.0, y300=0.34),
    'Other_Forest_Waste': dict(mc=20.0, y300=0.35),
}

for scen in ["near-term", "mature-market medium"]:
    sup = pd.read_csv(f"biochar_data_v2/{scen}/supply_matrix.csv")
    sup["dry"] = sup.apply(lambda r: r.capacity * (1 - FEEDSTOCKS[r.feedstock]["mc"] / 100), axis=1)
    sup["bc300_pot"] = sup.apply(lambda r: r.dry * FEEDSTOCKS[r.feedstock]["y300"], axis=1)
    print(f"{scen}: wet={sup.capacity.sum():,.0f}  dry={sup.dry.sum():,.0f}  bc300_pot={sup.bc300_pot.sum():,.0f}")
    print("   by feedstock:")
    g = sup.groupby("feedstock").agg(wet=("capacity","sum"), dry=("dry","sum"), pot=("bc300_pot","sum"))
    for name, row in g.iterrows():
        print(f"     {name:22s} wet={row.wet:>10,.0f} dry={row.dry:>9,.0f} pot300={row.pot:>8,.0f}")
