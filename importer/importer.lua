
-- vertex layout, общий с obj: position / texcoord / normal
local VERTEX_FMT = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexNormal',   'float', 3 },
}

importer = {
    obj     = require 'importer.formats.obj',
    gltf    = require 'importer.formats.gltf',
    texture = require 'importer.texture',
}

return importer
