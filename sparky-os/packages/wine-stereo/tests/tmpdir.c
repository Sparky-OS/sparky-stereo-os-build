/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void fatal_error( const char *format, ... )
{
    va_list args;
    va_start( args, format );
    vfprintf( stderr, format, args );
    va_end( args );
    exit( 2 );
}

#include "server_tmpdir.h"

int main( int argc, char **argv )
{
    struct stat st;
    char *first, *second, *marker;
    const char *root = secure_getenv( "TMPDIR" );
    if (argc != 2) return 2;
    if (!root) root = "/tmp";
    first = server_tmpdir( argv[1] );
    second = server_tmpdir( argv[1] );
    if (strcmp( first, second ) || strncmp( first, root, strlen( root ) ) ||
        first[strlen( root )] != '/' || stat( first, &st ) || !S_ISDIR( st.st_mode ) ||
        st.st_uid != getuid() || (st.st_mode & 0777) != 0700) return 3;
    if (asprintf( &marker, "%s/wineserver", argv[1] ) < 0) return 4;
    if (stat( marker, &st ) || st.st_uid != getuid() || (st.st_mode & 0777) != 0400) return 5;
    printf( "PASS create/read root=%s private_directory=0700 marker=0400\n", root );
    free( marker );
    free( second );
    free( first );
    return 0;
}
