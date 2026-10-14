/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A texture copied from a camera's window is view-dependent. Keep its right
 * view separately, including temporal feedback. Uploaded scene textures stay
 * shared until the program actually copies a camera image into them. */
static TextureTwin *texture_twin(GLuint name)
{
    for (TextureTwin *t=current ? current->textures : NULL;t;t=t->next)
        if (t->left==name) return t;
    return NULL;
}
static void free_texture_records(ContextState *context)
{
    while (context->textures) {
        TextureTwin *t=context->textures;context->textures=t->next;free(t);
    }
}
static int camera_copy_source(void)
{
    if (!current || current->quad || current->compiling || !current->window || !current->window->active) return 0;
    GLint framebuffer;r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&framebuffer);
    return !framebuffer;
}
static TextureTwin *copy_texture(void)
{
    if (!current || current->compiling) return NULL;
    GLint name;
    r_glGetIntegerv(GL_TEXTURE_BINDING_2D,&name);
    if (!name) return NULL;
    TextureTwin *t=texture_twin(name);
    if (t) return t;
    if (!camera_copy_source()) return NULL;
    t=calloc(1,sizeof(*t)); if (!t) return NULL;
    t->left=name; r_glGenTextures(1,&t->right);
    const GLenum parameters[]={GL_TEXTURE_MIN_FILTER,GL_TEXTURE_MAG_FILTER,GL_TEXTURE_WRAP_S,GL_TEXTURE_WRAP_T,GL_TEXTURE_BASE_LEVEL,GL_TEXTURE_MAX_LEVEL};
    for (unsigned i=0;i<sizeof(parameters)/sizeof(*parameters);i++) {
        GLint value; r_glGetTexParameteriv(GL_TEXTURE_2D,parameters[i],&value);
        r_glBindTexture(GL_TEXTURE_2D,t->right);r_glTexParameteri(GL_TEXTURE_2D,parameters[i],value);
        r_glBindTexture(GL_TEXTURE_2D,t->left);
    }
    GLfloat border[4];r_glGetTexParameterfv(GL_TEXTURE_2D,GL_TEXTURE_BORDER_COLOR,border);
    r_glBindTexture(GL_TEXTURE_2D,t->right);r_glTexParameterfv(GL_TEXTURE_2D,GL_TEXTURE_BORDER_COLOR,border);
    r_glBindTexture(GL_TEXTURE_2D,t->left);
    t->next=current->textures;current->textures=t;
    return t;
}
static void save_view_textures(DrawState *s)
{
    s->texture_count=0;
    if (!current->textures) return;
    GLint count; r_glGetIntegerv(GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS,&count);
    r_glGetIntegerv(GL_ACTIVE_TEXTURE,&s->active_texture);
    if (count>256) count=256;
    for (int unit=0;unit<count;unit++) {
        GLint binding;r_glActiveTexture(GL_TEXTURE0+unit);r_glGetIntegerv(GL_TEXTURE_BINDING_2D,&binding);
        TextureTwin *t=texture_twin(binding);
        if (t) { unsigned i=s->texture_count++;s->texture_unit[i]=unit;s->texture_left[i]=t->left;s->texture_right[i]=t->right; }
    }
    r_glActiveTexture(s->active_texture);
}
static void select_view_textures(const DrawState *s,int eye)
{
    if (!s->texture_count) return;
    for (unsigned i=0;i<s->texture_count;i++) {
        r_glActiveTexture(GL_TEXTURE0+s->texture_unit[i]);
        r_glBindTexture(GL_TEXTURE_2D,eye ? s->texture_right[i] : s->texture_left[i]);
    }
    r_glActiveTexture(s->active_texture);
}
static void restore_view_textures(const DrawState *s)
{
    if (!s->texture_count) return;
    GLint active;r_glGetIntegerv(GL_ACTIVE_TEXTURE,&active);
    for (unsigned i=0;i<s->texture_count;i++) {
        GLint binding;r_glActiveTexture(GL_TEXTURE0+s->texture_unit[i]);
        r_glGetIntegerv(GL_TEXTURE_BINDING_2D,&binding);
        if ((GLuint)binding==s->texture_right[i]) r_glBindTexture(GL_TEXTURE_2D,s->texture_left[i]);
    }
    r_glActiveTexture(active);
}
#pragma GCC visibility push(default)
void glCopyTexImage2D(GLenum target,GLint level,GLenum format,GLint x,GLint y,GLsizei width,GLsizei height,GLint border)
{
    API();TextureTwin *t=target==GL_TEXTURE_2D ? copy_texture() : NULL;
    r_glCopyTexImage2D(target,level,format,x,y,width,height,border);
    if (t) {
        r_glBindTexture(target,t->right);
        r_glCopyTexImage2D(target,level,format,x+(camera_copy_source() ? current->window->width : 0),y,width,height,border);
        r_glBindTexture(target,t->left);
    }
}
void glCopyTexSubImage2D(GLenum target,GLint level,GLint dx,GLint dy,GLint x,GLint y,GLsizei width,GLsizei height)
{
    API();GLint name;r_glGetIntegerv(GL_TEXTURE_BINDING_2D,&name);
    TextureTwin *t=target==GL_TEXTURE_2D && current && !current->compiling ? texture_twin(name) : NULL;
    r_glCopyTexSubImage2D(target,level,dx,dy,x,y,width,height);
    if (t) {
        r_glBindTexture(target,t->right);
        r_glCopyTexSubImage2D(target,level,dx,dy,x+(camera_copy_source() ? current->window->width : 0),y,width,height);
        r_glBindTexture(target,t->left);
    }
}
void glDeleteTextures(GLsizei count,const GLuint *names)
{
    API();
    for (int i=0;current && i<count;i++) {
        TextureTwin **p=&current->textures;
        while (*p && (*p)->left!=names[i]) p=&(*p)->next;
        if (*p) { TextureTwin *t=*p;*p=t->next;r_glDeleteTextures(1,&t->right);free(t); }
    }
    r_glDeleteTextures(count,names);
}
/* Later parameter changes apply to both instances of a camera texture. */
#define TEXTURE_PARAMETER(name,args,callargs) \
void name args { API(); r_##name callargs; \
    if (target==GL_TEXTURE_2D && current && !current->compiling) { \
        GLint binding;r_glGetIntegerv(GL_TEXTURE_BINDING_2D,&binding);TextureTwin *t=texture_twin(binding); \
        if (t) {r_glBindTexture(target,t->right);r_##name callargs;r_glBindTexture(target,t->left);} \
    } }
TEXTURE_PARAMETER(glTexParameteri,(GLenum target,GLenum parameter,GLint value),(target,parameter,value))
TEXTURE_PARAMETER(glTexParameterf,(GLenum target,GLenum parameter,GLfloat value),(target,parameter,value))
TEXTURE_PARAMETER(glTexParameteriv,(GLenum target,GLenum parameter,const GLint *value),(target,parameter,value))
TEXTURE_PARAMETER(glTexParameterfv,(GLenum target,GLenum parameter,const GLfloat *value),(target,parameter,value))
TEXTURE_PARAMETER(glTexImage2D,(GLenum target,GLint level,GLint internal,GLsizei width,GLsizei height,GLint border,GLenum format,GLenum type,const void *data),(target,level,internal,width,height,border,format,type,data))
TEXTURE_PARAMETER(glTexSubImage2D,(GLenum target,GLint level,GLint x,GLint y,GLsizei width,GLsizei height,GLenum format,GLenum type,const void *data),(target,level,x,y,width,height,format,type,data))
#undef TEXTURE_PARAMETER
#pragma GCC visibility pop
