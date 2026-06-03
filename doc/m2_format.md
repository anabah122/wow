# Формат: M2 → кастомный glTF + JSON

Переписываем парсер wowee (`wowee/src/pipeline/m2_loader.cpp`) с C++ на Lua **1:1,
ничего не вырезая**. Печём в glTF (геометрия) + JSON (всё остальное).

Правило: **в биты идёт ТОЛЬКО геометрия** (vertices/indices, glTF .bin).
Всё прочее — в JSON (читаемо, редактируемо, отлаживается глазами).

## Выход на одну модель

```
<name>.gltf   — стандартный glTF JSON: meshes/accessors/bufferViews/
                materials(базовое)/textures/images + skins + animations(bone TRS)
<name>.bin    — буфер геометрии + сэмплы анимаций костей
<name>.m2.json — M2-специфика, которой нет в стандарте glTF (см. ниже)
```

## Что КУДА (полная карта struct M2Model)

### → стандартный glTF (.gltf + .bin)
- `vertices` (position, normal, texCoords[2]) → accessors POSITION/NORMAL/TEXCOORD_0/_1
- `boneWeights[4]`, `boneIndices[4]` → WEIGHTS_0 / JOINTS_0
- `indices` → accessor SCALAR
- `bones` иерархия (parent, pivot) → nodes + skin (inverseBindMatrices)
- `bones` TRS-треки `translation/rotation/scale` → animations (channels/samplers)
- `textures.filename` → images (uri на .png рядом)
- `materials.blendMode` базово → material.alphaMode (грубо)

### → <name>.m2.json (всё, чего нет в glTF-стандарте)
Повторяем поля wowee как есть:

- **version**, **globalFlags**, **boundMin/Max/Radius**
- **materials[]**: `{flags, blendMode}` — flags биты:
  `0x01 Unlit, 0x02 Unfogged, 0x04 TwoSided, 0x08 DepthTest off, 0x10 DepthWrite off`
- **bones[]**: `{flags, keyBoneId, parentBone, submeshId, pivot}` —
  bone flags: billboard `0x08 spherical, 0x10 cylindrical-X, 0x20 cylindrical-Z` и т.д.
  (треки костей — в glTF animations; здесь только метаданные/флаги)
- **sequences[]**: `{id, variationIndex, duration, flags, frequency, replayMin/Max,
  blendTime, nextAnimation, aliasNext}` — нужно чтобы знать КАКУЮ анимацию играть
- **globalSequenceDurations[]**: длительности зацикленных глобал-последовательностей
- **batches[]**: `{flags, priorityPlane, shader, skinSectionIndex, colorIndex,
  materialIndex, materialLayer, textureCount, textureIndex, textureUnit,
  transparencyIndex, textureAnimIndex, indexStart/Count, vertexStart/Count,
  submeshId, submeshLevel}`
- **textureLookup[]**, **boneLookupTable[]**
- **textures[]**: `{type, flags, filename}` (type=кожа/волосы для замены)
- **textureTransforms[]** (UV-анимация: translation/rotation/scale треки) +
  **textureTransformLookup[]**
- **textureWeights[]** (анимация прозрачности per-batch)
- **colorAlphas[]** (анимация альфы цвета)
- **attachments[]**: `{id, bone, position}` + **attachmentLookup[]**
- **particleEmitters[]** (вся структура M2ParticleEmitter) — backlog рендера, но ПАРСИМ
- **ribbonEmitters[]** (вся структура M2RibbonEmitter) — backlog, но ПАРСИМ
- **collisionVertices/Indices/Normals** (для физики)

## Версии
**ТОЛЬКО WotLK (version >= 264).** Vanilla/TBS НЕ поддерживаем — выкидываем
весь version<264 код из wowee при переносе.
- WotLK: единый формат хедера, отдельный .skin файл (`<name>00.skin`),
  кости с boneNameCRC, sequences без extra-полей.

## Анимационные треки (M2AnimationTrack)
`{interpolationType (0 none/1 linear/2 hermite/3 bezier), globalSequence (-1 нет),
sequences[] = { timestamps[], vec3Values[] | quatValues[] | floatValues[] }}`
Bone TRS → glTF animation samplers. Прочие треки (UV/weight/color) → m2.json.
