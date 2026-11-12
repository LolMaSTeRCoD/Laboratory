# Anime head geometry source

Downloaded 2026-11-05 from the official MakeHuman Community CC0 asset pack:

- Index: https://static.makehumancommunity.org/assets/assetpacks/cartoon01.html
- Archive: https://files2.makehumancommunity.org/asset_packs/cartoon01/cartoon01_cc0.zip
- Asset: `spamrakuen_anime_stylized_enhanced_head_only`
- Author: spamrakuen / SpamRakuen
- Asset source: http://www.makehumancommunity.org/node/3344
- License: **CC0**, stated both in the official pack manifest and target header.
- Basemesh: hm08.

The author's description credits DredNicolson's Anime Stylized Enhanced and
restricts the deltas to the head. This is an anatomical vertex-offset target,
not a textured character model and not an Asta asset.

`anime-head-only.target` is an unchanged local copy of that target. The original
archive and its `packs/cartoon01.json` manifest are retained in `cartoon01/`.

SHA-256:

- Archive: `5d26425ba1266218e453e2f378fc432706554180a1fd1c6d1af0a6395d8f8c29`
- Target: `44c1095f6455ca71b9bfdf7651e5d1382a07248bbb5951732e9edf1dd7e25fe6`

The project uses it in Asta's reviewed facial geometry, with local smoothing
and fitted eyes. It does not establish an exact likeness to a character or supply a
license to the character design itself. Existing project references guide the
manual proportions, clothing, hair and equipment.

## Charmy child head morphology (2026-11-11)

- Asset: `jaldmic_anime_head_and_body_v6_chiby`.
- Author: **JALdMIC**.
- License: **CC0**, explicitly stated in the official MakeHuman Community
  [cartoon01 pack index](https://static.makehumancommunity.org/assets/assetpacks/cartoon01.html)
  (verified 2026-11-11) and retained `cartoon01/packs/cartoon01.json`, entry
  `jaldmic_anime_head_and_body_v6_chiby`.
- Original asset page: http://www.makehumancommunity.org/node/2950
  (not reachable during verification; the official pack index and manifest
  independently identify the asset, author and license).
- Distribution: the same official `cartoon01_cc0.zip` retained above.
- Local unmodified target:
  `cartoon01/targets/cartoon/jaldmic_anime_head_and_body_v6_chiby.target`.
- SHA-256: `6d53529dd98805aa13c6c414b3880685119d0c76a2023b141b5373fcaa5d271e`.

The target contains body deltas. KDTD applies only the smoothly masked head
region (`RAW` height 5.30 to 5.85) to Charmy, then adds the project's facial
proportions and fitted eyes. This target is an anatomical vertex deformation;
it contains no Charmy mesh, likeness texture or official character artwork.
Existing body rigging, skin weights and character animations are retained.
