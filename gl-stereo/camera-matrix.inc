/* SPDX-License-Identifier: GPL-2.0-or-later */
/* P*V retains row2.xyz = -A*row3.xyz for any affine view V.
 * Its constant B is row2.w + A*row3.w, even after camera rotation. */
static int camera_depth(const double p[16], double *a, double *b)
{
    double norm=0, dot=0;
    for (int i=0;i<16;i++) if (!isfinite(p[i])) return 0;
    for (int i=0;i<3;i++) { norm+=p[4*i+3]*p[4*i+3]; dot+=p[4*i+2]*p[4*i+3]; }
    if (norm<1e-12) return 0;
    *a=-dot/norm; *b=p[14]+*a*p[15];
    if (*a > -1+1e-6 || *b >= 0) return 0;
    for (int i=0;i<3;i++)
        if (fabs(p[4*i+2]+*a*p[4*i+3])>1e-5*sqrt(norm)) return 0;
    return 1;
}
static int inverse_matrix(const double input[16], double output[16])
{
    double rows[4][8];
    for (int i=0;i<4;i++) for (int j=0;j<8;j++) rows[i][j]=j<4 ? input[j*4+i] : j-4==i;
    for (int col=0;col<4;col++) {
        int pivot=col;
        for (int i=col+1;i<4;i++) if (fabs(rows[i][col])>fabs(rows[pivot][col])) pivot=i;
        if (fabs(rows[pivot][col])<1e-12) return 0;
        for (int j=0;j<8;j++) { double value=rows[col][j]; rows[col][j]=rows[pivot][j]; rows[pivot][j]=value; }
        double scale=rows[col][col];
        for (int j=0;j<8;j++) rows[col][j]/=scale;
        for (int i=0;i<4;i++) if (i!=col) {
            double factor=rows[i][col];
            for (int j=0;j<8;j++) rows[i][j]-=factor*rows[col][j];
        }
    }
    for (int i=0;i<4;i++) for (int j=0;j<4;j++) output[j*4+i]=rows[i][j+4];
    return 1;
}
static void select_fixed_camera(DrawState *s)
{
    s->camera_a=s->camera_b=0;
    s->perspective=camera_depth(s->projection,&s->camera_a,&s->camera_b);
    s->constant[0]=s->constant[1]=s->constant[2]=0; s->constant[3]=1;
    if (s->perspective || s->program || current->quad || current->core) return;
    double modelview[16], combined[16]={0}, inverse[16];
    r_glGetDoublev(GL_MODELVIEW_MATRIX,modelview);
    for (int c=0;c<4;c++) for (int r=0;r<4;r++) for (int k=0;k<4;k++)
        combined[c*4+r]+=s->projection[k*4+r]*modelview[c*4+k];
    if (!camera_depth(combined,&s->camera_a,&s->camera_b) || !inverse_matrix(modelview,inverse)) return;
    s->perspective=1;
    for (int c=0;c<4;c++) s->constant[c]=inverse[c*4+3];
}
