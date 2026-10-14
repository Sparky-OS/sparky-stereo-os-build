/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A unique canonical perspective matrix is an observable camera interface.
 * Leave ambiguous programs alone; names alone are not evidence of a camera. */
static int perspective_uniform(const GLfloat p[16])
{
    const int zero[] = {1,2,3,4,6,7,12,13,15};
    for (int i = 0; i < 16; ++i) if (!isfinite(p[i])) return 0;
    for (unsigned i = 0; i < sizeof(zero)/sizeof(*zero); ++i)
        if (fabs(p[zero[i]]) > 1e-6) return 0;
    return p[0] > 0 && p[5] > 0 && p[10] <= -1 && p[14] < 0 && fabs(p[11]+1) < 1e-6;
}
static void save_camera_uniform(DrawState *s)
{
    GLint count = 0, longest = 0;
    r_glGetProgramiv(s->program, GL_ACTIVE_UNIFORMS, &count);
    r_glGetProgramiv(s->program, GL_ACTIVE_UNIFORM_MAX_LENGTH, &longest);
    if (longest <= 0 || longest > 65536) return;
    char *name = malloc(longest);
    if (!name) return;
    for (int i = 0; i < count; ++i) {
        GLint size; GLenum type;
        r_glGetActiveUniform(s->program, i, longest, NULL, &size, &type, name);
        if (type != GL_FLOAT_MAT4 || size != 1) continue;
        GLint location = r_glGetUniformLocation(s->program, name);
        if (location < 0) continue;
        GLfloat matrix[16];
        r_glGetUniformfv(s->program, location, matrix);
        if (!perspective_uniform(matrix)) continue;
        if (s->projection_uniform >= 0) {
            s->projection_uniform = -1;
            memset(s->projection, 0, sizeof(s->projection));
            break;
        }
        s->projection_uniform = location;
        for (int j = 0; j < 16; ++j) s->projection[j] = matrix[j];
    }
    free(name);
}
static void load_camera_uniform(const DrawState *s, const double matrix[16])
{
    GLfloat values[16];
    for (int i = 0; i < 16; ++i) values[i] = matrix[i];
    r_glUniformMatrix4fv(s->projection_uniform, 1, GL_FALSE, values);
}
