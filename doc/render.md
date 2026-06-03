# Рендер-пайплайн моделей

Готовый пайплайн отрисовки моделей. Один шейдер, переключение униформами.

## Униформы-переключатели

- `uAlphaMode` — режим альфы (cutout discard threshold vs blend)
- `uDepthMul` — множитель глубины: `1.0` обычно, `0.99` для декалей.
  В вершинном шейдере: `gl_Position.z *= uDepthMul`.
  Множитель (не аддитивный сдвиг) — двигает именно глубину, не мировые
  координаты, к нулю не схлопывается.

**Depth test = `lequal` везде.**

## 4 пасса (по порядку)

| # | Пасс        | Cull | Blend          | Depth test | Depth write | uDepthMul |
|---|-------------|------|----------------|------------|-------------|-----------|
| 1 | Opaque      | back | replace        | lequal     | on          | 1.0       |
| 2 | Cutout      | none | alpha + discard| lequal     | on          | 1.0       |
| 3 | Decals      | back | alpha          | lequal     | on          | 0.99      |
| 4 | Transparent | none | alpha / add    | lequal     | **off**     | 1.0       |

- **Opaque** — непрозрачная геометрия.
- **Cutout** (blendMode 1, AlphaKey) — листва, решётки, цепи. Пиксель либо
  есть либо нет (`discard`). Твёрдый но дырявый — **пишет глубину**.
- **Decals** — декали (свиток на полу и т.п.). Пишут глубину, чтобы не
  просвечивать сквозь объекты перед ними, но `0.99` бьёт z-fight с
  совпадающим полом.
- **Transparent** (blendMode 2 Alpha, 3+ Add/Mod) — стекло, эффекты,
  свечение. Читают но **не пишут** глубину.

Внутри пасса — сортировка по текстуре/материалу, бинд blend только при смене.

`cull none` берётся из флага TwoSided (`flags & 0x04`).

## Маппинг M2 blendMode → LÖVE

M2 renderFlags-массив (`ofsRenderFlags`/`nRenderFlags`): элемент 4 байта =
`uint16 flags` + `uint16 blendMode`. Стандарт WoW EGxBlend.

| blendMode | имя WoW    | LÖVE setBlendMode        | depthWrite |
|-----------|------------|--------------------------|------------|
| 0         | Opaque     | `replace`                | on         |
| 1         | AlphaKey   | `alpha` + discard        | on         |
| 2         | Alpha      | `alpha`                  | off        |
| 3         | Add        | `add`                    | off        |
| 4         | Mod        | `multiply`               | off        |
| 5         | Mod2x      | ~`add` (приближение)     | off        |
| 6         | BlendAdd   | `add`,`alphamultiply`    | off        |
| 7         | Screen     | `screen`                 | off        |

`flags` (старший uint16): `0x01` Unlit, `0x02` Unfogged, `0x04` TwoSided,
`0x10` DepthWrite off.

Чёрные порталы/спеллы = на самом деле Add (blendMode 3-6), не AlphaKey:
при add чёрный (0,0,0) = прозрачный. Если гнать через alpha-test — чёрный квадрат.
