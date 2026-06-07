defmodule Showcase.OrderFlow.Seed do
  @moduledoc """
  Seeds the OrderFlow demo with synthetic clients, products, global product
  aliases (naïve Romanian terms → specific SKUs), and the curated demo
  inbox bundle.

  Implements `Showcase.Common.DemoSeeder` — invoked by the global Reset.

  Idempotent: every insert uses `on_conflict` so re-running produces identical state.

  ## Why the alias seed matters

  Many real customer messages don't reference SKUs — they say "balama" or
  "manere". The cascade `GlobalAliasStep` runs against `ProductAlias` rows
  with `client_id IS NULL`. Each entry maps one informal description to one
  authoritative SKU at a high confidence (seeded at 0.80), so during the
  live demo:

    * SKU-style line (`K1001-07-n03`) → **ExactStep** at confidence 1.0
    * Fuzzy variant (`biti ph2`)      → **FuzzyTrigramStep** (~0.6-0.9)
    * Informal name (`balama`)        → **GlobalAliasStep** at 0.80

  Three distinct cascade paths get visualized in the demo's right pane.
  """

  @behaviour Showcase.Common.DemoSeeder

  import Ecto.Query, only: [from: 2]

  alias Showcase.OrderFlow.MockPrompts
  alias Showcase.OrderFlow.Schemas.{Client, Product, ProductAlias, SyntheticMessage}
  alias Showcase.Repo

  @clients [
    # Meesenburg demo clients — match the senders of the live-demo PDFs.
    %{name: "Meesenburg Romania", email: "comenzi@meesenburg.ro"},
    %{name: "Alexandru Erdei", email: "alexandru.erdei@meesenburg.ro"},
    %{name: "Dragos Manolache", email: "dragosimcom@gmail.com"}
  ]

  # ── Catalog (130 products — full Meesenburg feronerie SKUs) ───────────
  # SKU naming follows the patterns observed in the Meesenburg PDFs:
  # K1001/2001/3001/4001/5001-XX-n03, A5000-series, plus named items.
  @products [
    # ── K1001 — Mânere ușă AXOR (10) ────────────────────────────────────
    %{sku: "K1001-01-n03", name: "Mâner ușă AXOR negru 28x92", normalized_name: "k1001-01-n03 maner usa axor negru"},
    %{sku: "K1001-07-n03", name: "Mâner ușă AXOR alb 28x92", normalized_name: "k1001-07-n03 maner usa axor alb"},
    %{sku: "K1001-11-n03", name: "Mâner ușă AXOR maro 28x92", normalized_name: "k1001-11-n03 maner usa axor maro"},
    %{sku: "K1001-13-n03", name: "Mâner ușă AXOR silver 28x92", normalized_name: "k1001-13-n03 maner usa axor silver"},
    %{sku: "K1001-16-n03", name: "Mâner ușă AXOR auriu 28x92", normalized_name: "k1001-16-n03 maner usa axor auriu"},
    %{sku: "K1001-18-n03", name: "Mâner ușă AXOR antichizat 28x92", normalized_name: "k1001-18-n03 maner usa axor antichizat"},
    %{sku: "K1001-21-n03", name: "Mâner ușă AXOR mat 28x92", normalized_name: "k1001-21-n03 maner usa axor mat"},
    %{sku: "K1001-25-n03", name: "Mâner ușă AXOR titan 28x92", normalized_name: "k1001-25-n03 maner usa axor titan"},
    %{sku: "K1001-30-n03", name: "Mâner ușă AXOR cromat 28x92", normalized_name: "k1001-30-n03 maner usa axor cromat"},
    %{sku: "K1001-35-n03", name: "Mâner ușă AXOR inox 28x92", normalized_name: "k1001-35-n03 maner usa axor inox"},

    # ── K2001/K2005 — Broaște & Blocuri (8) ─────────────────────────────
    %{sku: "K2001-00-n03", name: "Broască 1-punct", normalized_name: "k2001-00-n03 broasca 1 punct"},
    %{sku: "K2001-02-n03", name: "Broască multipunct 3-puncte", normalized_name: "k2001-02-n03 broasca multipunct 3 puncte"},
    %{sku: "K2001-04-n03", name: "Broască multipunct 5-puncte", normalized_name: "k2001-04-n03 broasca multipunct 5 puncte"},
    %{sku: "K2001-06-n03", name: "Broască multipunct ac. mâner (dintr-o bucată)", normalized_name: "k2001-06-n03 broasca multipunct ac maner dintr-o bucata"},
    %{sku: "K2005-00-n03", name: "Broască TOC G.EV 76", normalized_name: "k2005-00-n03 broasca toc gev 76"},
    %{sku: "K2005-01-n03", name: "Broască TOC G.EV 92", normalized_name: "k2005-01-n03 broasca toc gev 92"},
    %{sku: "K2005-02-n03", name: "Bloc TOC G.EV 76", normalized_name: "k2005-02-n03 bloc toc gev 76"},
    %{sku: "K2005-04-n03", name: "Bloc OB G.EV 76", normalized_name: "k2005-04-n03 bloc ob gev 76"},

    # ── K3001 — Colțare K-series (8) ────────────────────────────────────
    %{sku: "K3001-01-n03", name: "Colțar jos K1", normalized_name: "k3001-01-n03 coltar jos k1"},
    %{sku: "K3001-02-n03", name: "Colțar sus K1", normalized_name: "k3001-02-n03 coltar sus k1"},
    %{sku: "K3001-05-n03", name: "Colțar spate K1", normalized_name: "k3001-05-n03 coltar spate k1"},
    %{sku: "K3001-07-n03", name: "Colțar prag aluminiu", normalized_name: "k3001-07-n03 coltar prag aluminiu"},
    %{sku: "K3001-09-n03", name: "Colțar ciupercă", normalized_name: "k3001-09-n03 coltar ciuperca"},
    %{sku: "K3001-11-n03", name: "Colțar fără ciupercă", normalized_name: "k3001-11-n03 coltar fara ciuperca"},
    %{sku: "K3001-13-n03", name: "Colțar închidere suplimentar", normalized_name: "k3001-13-n03 coltar inchidere suplimentar"},
    %{sku: "K3001-15-n03", name: "Colțar oțel mare", normalized_name: "k3001-15-n03 coltar otel mare"},

    # ── K4001 — Mecanisme antiflambaj (8) ───────────────────────────────
    %{sku: "K4001-01-n03", name: "Mecanism antiflambaj 4-toc", normalized_name: "k4001-01-n03 mecanism antiflambaj 4 toc"},
    %{sku: "K4001-03-n03", name: "Mecanism antiflambaj 4-toc + ccv", normalized_name: "k4001-03-n03 mecanism antiflambaj 4 toc ccv"},
    %{sku: "K4001-06-n03", name: "Mecanism G.EV 76 antiflambaj", normalized_name: "k4001-06-n03 mecanism gev 76 antiflambaj"},
    %{sku: "K4001-09-n03", name: "Mecanism G.EV 76 standard", normalized_name: "k4001-09-n03 mecanism gev 76 standard"},
    %{sku: "K4001-11-n03", name: "Mecanism G.EV 92 antiflambaj", normalized_name: "k4001-11-n03 mecanism gev 92 antiflambaj"},
    %{sku: "K4001-13-n03", name: "Mecanism foarfecă 600/800", normalized_name: "k4001-13-n03 mecanism foarfeca 600 800"},
    %{sku: "K4001-15-n03", name: "Mecanism foarfecă 800/1000", normalized_name: "k4001-15-n03 mecanism foarfeca 800 1000"},
    %{sku: "K4001-17-n03", name: "Mecanism oscilo-batant", normalized_name: "k4001-17-n03 mecanism oscilo batant"},

    # ── K5001 — Cremoane & Tije stâlp (6) ───────────────────────────────
    %{sku: "K5001-13-n03", name: "Cremon ușă tip K", normalized_name: "k5001-13-n03 cremon usa tip k"},
    %{sku: "K5001-15-n03", name: "Cremon balcon", normalized_name: "k5001-15-n03 cremon balcon"},
    %{sku: "K5001-17-n03", name: "Tijă stâlp 1400-2000", normalized_name: "k5001-17-n03 tija stalp 1400 2000"},
    %{sku: "K5001-19-n03", name: "Tijă stâlp 2000-2400", normalized_name: "k5001-19-n03 tija stalp 2000 2400"},
    %{sku: "K5001-21-n03", name: "Tijă stâlp 2400-2800", normalized_name: "k5001-21-n03 tija stalp 2400 2800"},
    %{sku: "K5001-23-n03", name: "Tijă stâlp scurtă 800-1400", normalized_name: "k5001-23-n03 tija stalp scurta 800 1400"},

    # ── A-series — Accesorii (8) ────────────────────────────────────────
    %{sku: "A5001-00-n03", name: "Set accesorii fereastră bază", normalized_name: "a5001-00-n03 set accesorii fereastra baza"},
    %{sku: "A5006-00-n03", name: "Set accesorii fereastră premium", normalized_name: "a5006-00-n03 set accesorii fereastra premium"},
    %{sku: "A5010-00-n03", name: "Cuplaj prelungitor", normalized_name: "a5010-00-n03 cuplaj prelungitor"},
    %{sku: "A5012-00-n03", name: "Inel asigurare prelungitor", normalized_name: "a5012-00-n03 inel asigurare prelungitor"},
    %{sku: "A5015-00-n03", name: "Garnitură EPDM 6mm", normalized_name: "a5015-00-n03 garnitura epdm 6mm"},
    %{sku: "A5020-00-n03", name: "Garnitură EPDM 8mm", normalized_name: "a5020-00-n03 garnitura epdm 8mm"},
    %{sku: "A5025-00-n03", name: "Adeziv mecanism (tub)", normalized_name: "a5025-00-n03 adeziv mecanism tub"},
    %{sku: "A5030-00-n03", name: "Spray lubrifiant feronerie", normalized_name: "a5030-00-n03 spray lubrifiant feronerie"},

    # ── Brațe & Plăci FF — by size bracket (9) ──────────────────────────
    %{sku: "BRAT-FF-291-410-L", name: "Braț FF 291-410 stânga", normalized_name: "brat ff 291 410 stanga"},
    %{sku: "BRAT-FF-291-410-R", name: "Braț FF 291-410 dreapta", normalized_name: "brat ff 291 410 dreapta"},
    %{sku: "BRAT-FF-411-600-L", name: "Braț FF 411-600 stânga", normalized_name: "brat ff 411 600 stanga"},
    %{sku: "BRAT-FF-411-600-R", name: "Braț FF 411-600 dreapta", normalized_name: "brat ff 411 600 dreapta"},
    %{sku: "BRAT-FF-601-800-L", name: "Braț FF 601-800 stânga", normalized_name: "brat ff 601 800 stanga"},
    %{sku: "BRAT-FF-601-800-R", name: "Braț FF 601-800 dreapta", normalized_name: "brat ff 601 800 dreapta"},
    %{sku: "PL-FF-291-410", name: "Placă foarfecă 291-410", normalized_name: "placa foarfeca 291 410"},
    %{sku: "PL-FF-411-600", name: "Placă foarfecă 411-600", normalized_name: "placa foarfeca 411 600"},
    %{sku: "PL-FF-601-800", name: "Placă foarfecă 601-800", normalized_name: "placa foarfeca 601 800"},

    # ── Brațe & Plăci legacy named (4) ──────────────────────────────────
    %{sku: "PLC-FF-600-800", name: "Placă foarfecă 600/800", normalized_name: "placa foarfeca 600 800 legacy"},
    %{sku: "BRT-DR-600-800", name: "Braț dreapta 600/800", normalized_name: "brt dr 600 800 dreapta legacy"},
    %{sku: "BRT-SG-600-800", name: "Braț stânga 600/800", normalized_name: "brt sg 600 800 stanga legacy"},
    %{sku: "BRT-EXT-1000", name: "Braț extensibil 1000mv", normalized_name: "brat extensibil 1000 mv"},

    # ── Prelungitoare (8) ───────────────────────────────────────────────
    %{sku: "PRL-1E-200-PRI", name: "Prelungitor 1E 200mv principal", normalized_name: "prelungitor 1e 200 mv principal"},
    %{sku: "PRL-1E-200-SEK", name: "Prelungitor 1E 200mv secundar", normalized_name: "prelungitor 1e 200 mv secundar"},
    %{sku: "PRL-1E-400", name: "Prelungitor 1E fără cuplă 400mv", normalized_name: "prelungitor 1e fara cupla 400 mv"},
    %{sku: "PRL-1E-600-CU", name: "Prelungitor 1E 600mv cu cuplare", normalized_name: "prelungitor 1e 600 mv cu cuplare"},
    %{sku: "PRL-1E-600-FC", name: "Prelungitor 1E 600mv fără cuplare", normalized_name: "prelungitor 1e 600 mv fara cuplare"},
    %{sku: "PRL-1E-800", name: "Prelungitor 1E 800mv", normalized_name: "prelungitor 1e 800 mv"},
    %{sku: "PRL-1E-1000", name: "Prelungitor 1E 1000mv", normalized_name: "prelungitor 1e 1000 mv"},
    %{sku: "PRL-COL-200", name: "Cuplaj prelungitor 200", normalized_name: "cuplaj prelungitor 200"},

    # ── Colțare named (5) ───────────────────────────────────────────────
    %{sku: "COLT-JOS", name: "Colțar jos universal", normalized_name: "coltar jos universal standard"},
    %{sku: "COLT-SUS", name: "Colțar sus universal", normalized_name: "coltar sus universal standard"},
    %{sku: "COLT-SPATE", name: "Colțar spate universal", normalized_name: "coltar spate universal standard"},
    %{sku: "COLT-CIU", name: "Colțar cu ciupercă", normalized_name: "coltar cu ciuperca standard"},
    %{sku: "COLT-FCIU", name: "Colțar fără ciupercă", normalized_name: "coltar fara ciuperca standard"},

    # ── Balamale & Semibalamale (10) ────────────────────────────────────
    %{sku: "BAL-USA-MARO", name: "Balamale ușă maro", normalized_name: "balamale usa maro standard"},
    %{sku: "BAL-USA-ALB", name: "Balamale ușă alb", normalized_name: "balamale usa alb standard"},
    %{sku: "BAL-USA-NEGRU", name: "Balamale ușă negru", normalized_name: "balamale usa negru standard"},
    %{sku: "BAL-USA-SLV", name: "Balamale ușă silver", normalized_name: "balamale usa silver standard"},
    %{sku: "BAL-ANTIFL", name: "Balamale antiflambaj 4-toc + ccv", normalized_name: "balamale antiflambaj 4 toc ccv"},
    %{sku: "BAL-SD-STG", name: "Balama SD stânga", normalized_name: "balama sd stanga"},
    %{sku: "BAL-SD-DR", name: "Balama SD dreapta", normalized_name: "balama sd dreapta"},
    %{sku: "SEMIBAL-INF-TOC", name: "Semibalama inferioară TOC", normalized_name: "semibalama inferioara toc"},
    %{sku: "SEMIBAL-INF-CERC", name: "Semibalama inferioară cerc", normalized_name: "semibalama inferioara cerc"},
    %{sku: "RBAL-AX", name: "RBAL AX", normalized_name: "rbal ax 50"},

    # ── Mecanisme OB & TOC G.EV (6) ─────────────────────────────────────
    %{sku: "MEC-OB-1800", name: "Mecanism OB 1400-1800", normalized_name: "mecanism ob 1400 1800"},
    %{sku: "MEC-OB-2400", name: "Mecanism OB 2000-2400", normalized_name: "mecanism ob 2000 2400"},
    %{sku: "MEC-OB-2800", name: "Mecanism OB 2400-2800", normalized_name: "mecanism ob 2400 2800"},
    %{sku: "BLOC-OB-GEV76", name: "Bloc OB G.EV 76", normalized_name: "bloc ob gev 76 standard"},
    %{sku: "BLOC-TOC-GEV76", name: "Bloc TOC G.EV 76", normalized_name: "bloc toc gev 76 standard"},
    %{sku: "BAL-ANTIFL-GEV76", name: "Balamale antiflambaj G.EV 76", normalized_name: "balamale antiflambaj gev 76"},

    # ── Profile AXOR cod numeric (6 — VRG 311 page 2) ───────────────────
    %{sku: "AXOR-795389", name: "Profil mâner AXOR cod 795389", normalized_name: "profil maner axor 795389"},
    %{sku: "AXOR-255282", name: "Profil mâner AXOR cod 255282", normalized_name: "profil maner axor 255282"},
    %{sku: "AXOR-2028266", name: "Profil mâner AXOR cod 2028266", normalized_name: "profil maner axor 2028266"},
    %{sku: "AXOR-450821", name: "Profil mâner AXOR cod 450821", normalized_name: "profil maner axor 450821"},
    %{sku: "AXOR-450822", name: "Profil mâner AXOR cod 450822", normalized_name: "profil maner axor 450822"},
    %{sku: "AXOR-390674", name: "Profil mâner AXOR cod 390674", normalized_name: "profil maner axor 390674"},

    # ── Diverse (8) ─────────────────────────────────────────────────────
    %{sku: "BIT-PH2-BOX", name: "Biți PH2 (cutie 20 buc)", normalized_name: "biti ph2 cutie 20 buc"},
    %{sku: "BIT-PH3-BOX", name: "Biți PH3 (cutie 20 buc)", normalized_name: "biti ph3 cutie 20 buc"},
    %{sku: "BIT-TX25-BOX", name: "Biți Torx TX25 cutie", normalized_name: "biti torx tx25 cutie"},
    %{sku: "ZAVOR-VAR-1200", name: "Zăvor vară 801-1200", normalized_name: "zavor vara 801 1200"},
    %{sku: "SUPORT-SD", name: "Suport SD universal", normalized_name: "suport sd universal"},
    %{sku: "BROASCA-AC", name: "Broască multipunct ac. mâner", normalized_name: "broasca multipunct ac maner standard"},
    %{sku: "BROASCA-1B", name: "Broască multipunct dintr-o bucată", normalized_name: "broasca multipunct dintr-o bucata"},
    %{sku: "TAMP-EPDM", name: "Tampon EPDM ferestre", normalized_name: "tampon epdm ferestre"},

    # ── AXOR feronerie (26 — from VRG 311 PDF page 2 / Tamistef Botoșani) ──
    %{sku: "AX-LAGAR-BAL-SUP-TOC", name: "AXOR lăgăr balama superioară TOC cu știft", normalized_name: "axor lagar balama superioara toc cu stift"},
    %{sku: "AX-BAL-INF-TOC-100", name: "AXOR balama inferioară TOC 100KG", normalized_name: "axor balama inferioara toc 100 kg"},
    %{sku: "AX-BAL-INF-CCV-100", name: "AXOR balama inferioară cercevea 100KG", normalized_name: "axor balama inferioara cercevea 100 kg"},
    %{sku: "AX-CONTRA-CANAT", name: "AXOR contraacționare greșită pt. mec. canat inactiv", normalized_name: "axor contraactionare gresita mec canat inactiv"},
    %{sku: "AX-CONTRA-TOC", name: "AXOR contraacționare greșită TOC Aluplast/Rehau/Veka", normalized_name: "axor contraactionare gresita toc aluplast rehau veka"},
    %{sku: "AX-CONTRA-CCV", name: "AXOR contraacționare greșită cercevea", normalized_name: "axor contraactionare gresita cercevea"},
    %{sku: "AX-CAPAC-SUP-CCV-BRZ", name: "AXOR capac superior cercevea bronz", normalized_name: "axor capac superior cercevea bronz"},
    %{sku: "AX-CAPAC-LAGAR-TOC-BRZ", name: "AXOR capac lăgăr superior TOC bronz", normalized_name: "axor capac lagar superior toc bronz"},
    %{sku: "AX-CAPAC-INF-CCV-BRZ", name: "AXOR capac inferior cercevea bronz", normalized_name: "axor capac inferior cercevea bronz"},
    %{sku: "AX-CAPAC-INF-TOC-MIC", name: "AXOR capac inferior TOC mic bronz", normalized_name: "axor capac inferior toc mic bronz"},
    %{sku: "AX-CAPAC-INF-TOC-LUNG", name: "AXOR capac inferior TOC lung bronz", normalized_name: "axor capac inferior toc lung bronz"},
    %{sku: "AX-BLOCAJ-TOC-13", name: "AXOR blocaj TOC Aluplast/Rehau/Salamander AX 13mm", normalized_name: "axor blocaj toc aluplast rehau salamander ax 13mm"},
    %{sku: "BAL-ANTIFL-CCV", name: "Balamale antiflambaj cercevea", normalized_name: "balamale antiflambaj cercevea"},
    %{sku: "BAL-ANTIFL-TOC-13", name: "Balamale antiflambaj TOC AX 13mm", normalized_name: "balamale antiflambaj toc ax 13mm"},
    %{sku: "AX-CREMON-OB-1230", name: "AXOR cremon OB variabil 751-1230mm GR930", normalized_name: "axor cremon ob variabil 751 1230mm gr930"},
    %{sku: "AX-CREMON-OB-2390", name: "AXOR cremon OB variabil 1911-2390mm GR2090", normalized_name: "axor cremon ob variabil 1911 2390mm gr2090"},
    %{sku: "AX-MEC-CANAT-1430", name: "AXOR mecanism canat inactiv 951-1430mm 1E", normalized_name: "axor mecanism canat inactiv 951 1430mm 1e"},
    %{sku: "AX-COLT-EGAL-150", name: "AXOR colțar egal 150x150mm 1P", normalized_name: "axor coltar egal 150 150mm 1p"},
    %{sku: "AX-FOARF-OB-600", name: "AXOR foarfecă OB 430-600mm 0E", normalized_name: "axor foarfeca ob 430 600mm 0e"},
    %{sku: "AX-FOARF-OB-800", name: "AXOR foarfecă OB 601-800mm 0E", normalized_name: "axor foarfeca ob 601 800mm 0e"},
    %{sku: "AX-PRL-INF-CREM", name: "AXOR prelungitor inferior deschidere simplă pt. cremon variabil", normalized_name: "axor prelungitor inferior deschidere simpla cremon variabil"},
    %{sku: "AX-INCH-SPATE-1250", name: "AXOR închidere spate 1V+1E 850-1250mm", normalized_name: "axor inchidere spate 1v 1e 850 1250mm"},
    %{sku: "AX-BAL-SUP-CCV-13", name: "AXOR balama superioară cercevea AX 13mm 12/20-13", normalized_name: "axor balama superioara cercevea ax 13mm"},
    %{sku: "AX-SEMIBAL-SUP-CCV", name: "AXOR semibalama superioară CCV simplă deschidere", normalized_name: "axor semibalama superioara ccv simpla deschidere"},
    %{sku: "AX-BLOCAJ-SIG", name: "AXOR blocaj siguranță Aluplast/Rehau/Salamander/Veka", normalized_name: "axor blocaj siguranta aluplast rehau salamander veka"},
    %{sku: "AX-BLOCAJ-OB-SIG", name: "AXOR blocaj OB de siguranță Veka AX 13mm", normalized_name: "axor blocaj ob de siguranta veka ax 13mm"}
  ]

  # ── Global aliases — informal Romanian → SKU ───────────────────────────
  # Each entry seeds a `ProductAlias` row with `client_id IS NULL` at
  # confidence 0.80. When the cascade's FuzzyStep misses (similarity < 0.5),
  # GlobalAliasStep fires and produces a clean match.
  @global_aliases [
    {"balama", "BAL-USA-MARO"},
    {"balamale", "BAL-USA-MARO"},
    {"balamale antiflambaj", "BAL-ANTIFL"},
    {"semibalama", "SEMIBAL-INF-TOC"},
    {"semibalamale", "SEMIBAL-INF-TOC"},
    {"maner", "K1001-07-n03"},
    {"manere", "K1001-07-n03"},
    {"maner usa", "K1001-07-n03"},
    {"manere usa", "K1001-07-n03"},
    {"broasca", "K2001-06-n03"},
    {"broasca usa", "K2001-06-n03"},
    {"broasca multipunct", "K2001-06-n03"},
    {"coltar", "COLT-JOS"},
    {"coltare", "COLT-JOS"},
    {"coltar jos", "COLT-JOS"},
    {"coltar sus", "COLT-SUS"},
    {"coltar spate", "COLT-SPATE"},
    {"coltar ciuperca", "COLT-CIU"},
    {"coltar fara ciuperca", "COLT-FCIU"},
    {"tija", "K5001-19-n03"},
    {"tija stulp", "K5001-19-n03"},
    {"tija stalp", "K5001-19-n03"},
    {"prelungitor", "PRL-1E-400"},
    {"prel", "PRL-1E-400"},
    {"placa foarfeca", "PLC-FF-600-800"},
    {"foarfeca", "PLC-FF-600-800"},
    {"brat", "BRT-DR-600-800"},
    {"brat dreapta", "BRT-DR-600-800"},
    {"brat stanga", "BRT-SG-600-800"},
    {"mecanism", "MEC-OB-2400"},
    {"mecanism ob", "MEC-OB-2400"},
    {"mecanism ob 2400", "MEC-OB-2400"},
    {"mecanism ob 2000-2400", "MEC-OB-2400"},
    {"mecanism antiflambaj", "K4001-03-n03"},
    {"bloc ob", "BLOC-OB-GEV76"},
    {"bloc toc", "BLOC-TOC-GEV76"},
    {"zavor", "ZAVOR-VAR-1200"},
    {"zavor vara", "ZAVOR-VAR-1200"},
    {"biti", "BIT-PH2-BOX"},
    {"biti ph2", "BIT-PH2-BOX"},
    {"cremon", "K5001-13-n03"},
    {"suport", "SUPORT-SD"},
    {"suport sd", "SUPORT-SD"},
    {"garnitura", "A5015-00-n03"},
    {"cuplaj", "A5010-00-n03"},
    {"spray", "A5030-00-n03"},
    {"lubrifiant", "A5030-00-n03"}
  ]

  @impl true
  def name, do: "OrderFlow"

  @impl true
  def description do
    "Turn unstructured customer messages into structured orders, with the system getting smarter every time a human corrects it."
  end

  @impl true
  def tables do
    # children before parents (for TRUNCATE order)
    [
      "of_order_lines",
      "of_orders",
      "of_product_aliases",
      "of_synthetic_messages",
      "of_products",
      "of_clients"
    ]
  end

  @impl true
  def oban_queue, do: :order_flow

  @impl true
  def seed do
    Repo.transaction(fn ->
      seed_clients()
      seed_products()
      seed_aliases()
      seed_messages()
    end)
    |> case do
      {:ok, _} ->
        seed_system_prompts()
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp seed_system_prompts do
    Showcase.Common.SystemPromptSeeder.upsert(
      "order_flow",
      "extraction",
      Showcase.OrderFlow.Extraction.system_prompt(),
      note: "Extracts client + line items from raw message text."
    )

    Showcase.Common.SystemPromptSeeder.upsert(
      "order_flow",
      "claude_fallback",
      Showcase.OrderFlow.Cascade.ClaudeFallbackStep.system_prompt(),
      note: "Last-resort product match when fuzzy + alias steps miss."
    )
  end

  defp seed_clients do
    Enum.each(@clients, fn attrs ->
      %Client{}
      |> Client.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
    end)
  end

  defp seed_products do
    Enum.each(@products, fn attrs ->
      %Product{}
      |> Product.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :sku)
    end)
  end

  defp seed_aliases do
    now = DateTime.utc_now()

    # Seed all global aliases (client_id: NULL) at confidence 0.80.
    Enum.each(@global_aliases, fn {alias_text, sku} ->
      case Repo.get_by(Product, sku: sku) do
        nil ->
          :ok

        %Product{} = product ->
          existing =
            Repo.one(
              from a in ProductAlias,
                where:
                  a.normalized_text == ^alias_text and
                    a.product_id == ^product.id and
                    is_nil(a.client_id)
            )

          unless existing do
            %ProductAlias{}
            |> ProductAlias.changeset(%{
              normalized_text: alias_text,
              product_id: product.id,
              client_id: nil,
              confidence: 0.80,
              last_used_at: now,
              use_count: 1,
              source: "seed"
            })
            |> Repo.insert!()
          end
      end
    end)
  end

  defp seed_messages do
    # Only seed the 3 demo-pitch scenarios — older ones stay in MockPrompts
    # for test-time Mock registration but don't appear in the demo inbox.
    Enum.each(MockPrompts.seed_scenarios(), fn s ->
      existing = Repo.get_by(SyntheticMessage, scenario: s.name)

      unless existing do
        %SyntheticMessage{}
        |> SyntheticMessage.changeset(%{
          body: s.body,
          kind: s.kind,
          scenario: s.name,
          client_hint: s.client_hint,
          from_address: Map.get(s, :from_address),
          subject: Map.get(s, :subject),
          attachment_paths: [],
          composed: false
        })
        |> Repo.insert!()
      end
    end)
  end
end
