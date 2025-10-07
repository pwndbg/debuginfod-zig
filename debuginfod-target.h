typedef struct debuginfod_client debuginfod_client;

/* Create a handle for a new debuginfod-client session.  */
debuginfod_client *debuginfod_begin (void);

/* Query the urls contained in $DEBUGINFOD_URLS for a file with
   the specified type and build id.  If build_id_len == 0, the
   build_id is supplied as a lowercase hexadecimal string; otherwise
   it is a binary blob of given length.

   If successful, return a file descriptor to the target, otherwise
   return a negative POSIX error code.  If successful, set *path to a
   strdup'd copy of the name of the same file in the cache.  Caller
   must free() it later. */

int debuginfod_find_debuginfo (debuginfod_client *client,
			       const unsigned char *build_id,
                               int build_id_len,
                               char **path);

int debuginfod_find_executable (debuginfod_client *client,
				const unsigned char *build_id,
                                int build_id_len,
                                char **path);

int debuginfod_find_source (debuginfod_client *client,
			    const unsigned char *build_id,
                            int build_id_len,
                            const char *filename,
                            char **path);

typedef int (*debuginfod_progressfn_t)(debuginfod_client *c, long a, long b);
void debuginfod_set_progressfn(debuginfod_client *c,
			       debuginfod_progressfn_t fn);

/* Release debuginfod client connection context handle.  */
void debuginfod_end (debuginfod_client *client);
