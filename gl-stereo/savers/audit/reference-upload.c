/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Test-only camera-upload oracle for programs putting GLU perspective in MODELVIEW. */
#define _GNU_SOURCE
#include <GL/gl.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
void gluPerspective(GLdouble fov,GLdouble aspect,GLdouble near,GLdouble far)
{
 double top=near*tan(fov*M_PI/360),right=top*aspect;
 double convergence=getenv("REFERENCE_CONVERGENCE")?atof(getenv("REFERENCE_CONVERGENCE")):5*near;
 double percent=getenv("REFERENCE_SEPARATION")?atof(getenv("REFERENCE_SEPARATION")):2;
 double half_eye=convergence*percent*right/(100*near);
 if(getenv("REFERENCE_EYE") && !strcmp(getenv("REFERENCE_EYE"),"right")) half_eye=-half_eye;
 double offset=half_eye*near/convergence;
 glFrustum(-right+offset,right+offset,-top,top,near,far);
 glTranslated(half_eye,0,0);
}
