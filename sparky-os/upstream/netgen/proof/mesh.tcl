Ng_LoadGeometry /w/three.geo
Ng_ParseGeometry
after 1500 {
  Ng_GenerateMesh ag ov
  Ng_ReadStatus
  set selectvisual mesh
  Ng_SetVisParameters
  redraw
}
