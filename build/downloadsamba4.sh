#!/bin/sh
set -eu

. "$(dirname "$0")/env.sh"

mkdir -p "$OUT" "$SAMBA4_WORK"

{
    echo "Starting Samba 4 download workflow at $(date -u)"
    echo "SAMBA4_VERSION=$SAMBA4_VERSION"
    echo "SAMBA4_GIT_URL=$SAMBA4_GIT_URL"
    echo "SAMBA4_GIT_REF=$SAMBA4_GIT_REF"
    echo "SAMBA4_FALLBACK_VERSION=$SAMBA4_FALLBACK_VERSION"
    echo "SAMBA4_FALLBACK_GIT_REF=$SAMBA4_FALLBACK_GIT_REF"
    echo "SAMBA4_SRC_DIR=$SAMBA4_SRC_DIR"

    # Samba 4.2 waf expects a host-side Python 2 environment on the VM.
    echo "This part is installing Python 2.7 on the VM with pkgin so Samba 4 waf can find the host interpreter and headers."
    if pkg_info python27 >/dev/null 2>&1; then
        echo "python27 is already installed on the VM; skipping pkgin install."
    else
        /usr/pkg/bin/pkgin -y install python27
    fi

    if [ -d "$SAMBA4_SRC_DIR/.git" ]; then
        printf 'Refreshing existing git checkout at %s\n' "$SAMBA4_SRC_DIR"
        git -C "$SAMBA4_SRC_DIR" fetch --depth 1 origin "$SAMBA4_GIT_REF"
        git -C "$SAMBA4_SRC_DIR" checkout -B "$SAMBA4_GIT_REF" "FETCH_HEAD"
        git -C "$SAMBA4_SRC_DIR" reset --hard "FETCH_HEAD"
    elif [ -d "$SAMBA4_SRC_DIR" ]; then
        printf 'Removing existing non-git Samba source tree at %s\n' "$SAMBA4_SRC_DIR"
        rm -rf "$SAMBA4_SRC_DIR"
        git clone --depth 1 --branch "$SAMBA4_GIT_REF" "$SAMBA4_GIT_URL" "$SAMBA4_SRC_DIR"
    else
        git clone --depth 1 --branch "$SAMBA4_GIT_REF" "$SAMBA4_GIT_URL" "$SAMBA4_SRC_DIR"
    fi

    perl -0pi -e 's/perl_inc = read_perl_config_var\('\''print "\@INC"'\''\)\n(?:\s*if '\''\.'\'' in perl_inc:\n)*(?:\s*perl_inc\.remove\('\''\.'\''\)\n)?/perl_inc = read_perl_config_var('\''print "\@INC"'\'')\n    if '\''.'\'' in perl_inc:\n        perl_inc.remove('\''.'\'')\n/s' \
        "$SAMBA4_SRC_DIR/buildtools/wafsamba/samba_perl.py"
    perl -0pi -e 's/#ifndef PRINT_MAX_JOBID/#include <time.h>\n\n#ifndef PRINT_MAX_JOBID/' \
        "$SAMBA4_SRC_DIR/lib/param/loadparm.h"
    perl -0pi -e 's/conf\.SAMBA_CHECK_PYTHON_HEADERS\(mandatory=True\)/conf.SAMBA_CHECK_PYTHON_HEADERS(mandatory=False)/g' \
        "$SAMBA4_SRC_DIR/wscript" \
        "$SAMBA4_SRC_DIR/ctdb/wscript" \
        "$SAMBA4_SRC_DIR/lib/ldb/wscript"
    perl -0pi -e 's/conf\.SAMBA_CHECK_PYTHON_HEADERS\(mandatory=\(not conf\.env\.disable_python\)\)/conf.SAMBA_CHECK_PYTHON_HEADERS(mandatory=False)/g' \
        "$SAMBA4_SRC_DIR/wscript" \
        "$SAMBA4_SRC_DIR/lib/ldb/wscript"
    perl -0pi -e 's/conf\.SAMBA_CHECK_PYTHON_HEADERS\(mandatory=not conf\.env\.disable_python\)/conf.SAMBA_CHECK_PYTHON_HEADERS(mandatory=False)/g' \
        "$SAMBA4_SRC_DIR/lib/ldb/wscript"
    perl -0pi -e 's/conf\.SAMBA_CHECK_PYTHON_HEADERS\(mandatory=False\)\n/conf.SAMBA_CHECK_PYTHON_HEADERS(mandatory=False)\n    conf.env.disable_python = not conf.env.HAVE_PYTHON_H\n/' \
        "$SAMBA4_SRC_DIR/wscript"
    perl -0pi -e 's/enabled=enabled\)/enabled=(enabled and not bld.env.disable_python and bld.CONFIG_SET('\''HAVE_PYTHON_H'\'')))/' \
        "$SAMBA4_SRC_DIR/buildtools/wafsamba/samba_python.py"

    awk '
        BEGIN { wrap = 0 }
        !wrap && /^bld\.SAMBA_SUBSYSTEM\('\''pyrpc_util'\''/ {
            print "if not bld.env.disable_python:"
            wrap = 1
        }
        {
            if (wrap) {
                print "    " $0
                if ($0 ~ /^\t\)$/) {
                    print "else:"
                    print "    bld.SAMBA_SUBSYSTEM('\''pyrpc_util'\'', source='\'''\'')"
                    wrap = 0
                }
            } else {
                print
            }
        }
    ' "$SAMBA4_SRC_DIR/source4/librpc/wscript_build" >"$SAMBA4_SRC_DIR/source4/librpc/wscript_build.tmp"
    mv "$SAMBA4_SRC_DIR/source4/librpc/wscript_build.tmp" "$SAMBA4_SRC_DIR/source4/librpc/wscript_build"

    awk '
        BEGIN { wrap = 0 }
        !wrap && /^bld\.SAMBA_SUBSYSTEM\('\''PROVISION'\''/ {
            print "if not bld.env.disable_python:"
            wrap = 1
        }
        {
            if (wrap) {
                print "    " $0
                if ($0 ~ /^\t\)$/) {
                    print "else:"
                    print "    bld.SAMBA_SUBSYSTEM('\''PROVISION'\'', source='\'''\'')"
                    wrap = 0
                }
            } else {
                print
            }
        }
    ' "$SAMBA4_SRC_DIR/source4/param/wscript_build" >"$SAMBA4_SRC_DIR/source4/param/wscript_build.tmp"
    mv "$SAMBA4_SRC_DIR/source4/param/wscript_build.tmp" "$SAMBA4_SRC_DIR/source4/param/wscript_build"

    awk '
        BEGIN { wrap = 0 }
        !wrap && /^bld\.SAMBA_SUBSYSTEM\('\''pyparam_util'\''/ {
            print "if not bld.env.disable_python:"
            wrap = 1
        }
        {
            if (wrap) {
                print "    " $0
                if ($0 ~ /^\t\)$/) {
                    print "else:"
                    print "    bld.SAMBA_SUBSYSTEM('\''pyparam_util'\'', source='\'''\'')"
                    wrap = 0
                }
            } else {
                print
            }
        }
    ' "$SAMBA4_SRC_DIR/source4/param/wscript_build" >"$SAMBA4_SRC_DIR/source4/param/wscript_build.tmp"
    mv "$SAMBA4_SRC_DIR/source4/param/wscript_build.tmp" "$SAMBA4_SRC_DIR/source4/param/wscript_build"

    cat >"$SAMBA4_SRC_DIR/python/wscript_build" <<'EOF'
#!/usr/bin/env python

if not bld.env.disable_python:
    bld.SAMBA_LIBRARY('samba_python',
        source=[],
        deps='LIBPYTHON pytalloc-util pyrpc_util',
        grouping_library=True,
        private_library=True,
        pyembed=True)

    bld.SAMBA_SUBSYSTEM('LIBPYTHON',
        source='modules.c',
        public_deps='',
        init_function_sentinel='{NULL,NULL}',
        deps='talloc',
        pyext=True,
        )

    bld.SAMBA_PYTHON('python_uuid',
        source='uuidmodule.c',
        deps='ndr',
        realname='uuid.so',
        enabled = float(bld.env.PYTHON_VERSION) <= 2.4
        )

    bld.SAMBA_PYTHON('python_glue',
        source='pyglue.c',
        deps='pyparam_util samba-util netif pytalloc-util',
        realname='samba/_glue.so'
        )

    bld.SAMBA_SCRIPT('samba_python_files',
        pattern='samba/**/*.py',
        installdir='python')

    bld.INSTALL_WILDCARD('${PYTHONARCHDIR}', 'samba/**/*.py', flat=False)
EOF

    perl -0pi -e "s/SRC = '''tevent\\.c tevent_debug\\.c tevent_fd\\.c tevent_immediate\\.c\\n             tevent_queue\\.c tevent_req\\.c\\n             tevent_poll\\.c tevent_threads\\.c\\n             tevent_signal\\.c tevent_standard\\.c tevent_timed\\.c tevent_util\\.c tevent_wakeup\\.c'''/SRC = '''tevent.c tevent_debug.c tevent_fd.c tevent_immediate.c\\n             tevent_queue.c tevent_req.c\\n             tevent_poll.c\\n             tevent_signal.c tevent_standard.c tevent_timed.c tevent_util.c tevent_wakeup.c'''\\n\\n    if bld.CONFIG_SET('HAVE_PTHREAD'):\\n        SRC += ' tevent_threads.c'/s" \
        "$SAMBA4_SRC_DIR/lib/tevent/wscript"
    perl -0pi -e "s/\\n\\ttevent_poll_init\\(\\);\\n\\ttevent_poll_mt_init\\(\\);/\\n\\ttevent_poll_init();\\n#ifdef HAVE_PTHREAD\\n\\ttevent_poll_mt_init();\\n#endif/s" \
        "$SAMBA4_SRC_DIR/lib/tevent/tevent.c"
    perl -0pi -e "s/\\n\\tif \\(ev->threaded_contexts != NULL\\) \\{\\n\\t\\ttevent_common_threaded_activate_immediate\\(ev\\);\\n\\t\\}/\\n#ifdef HAVE_PTHREAD\\n\\tif (ev->threaded_contexts != NULL) {\\n\\t\\ttevent_common_threaded_activate_immediate(ev);\\n\\t}\\n#endif/s" \
        "$SAMBA4_SRC_DIR/lib/tevent/tevent_poll.c"
    perl -0pi -e "s/\\n\\tif \\(ev->threaded_contexts != NULL\\) \\{\\n\\t\\ttevent_common_threaded_activate_immediate\\(ev\\);\\n\\t\\}/\\n#ifdef HAVE_PTHREAD\\n\\tif (ev->threaded_contexts != NULL) {\\n\\t\\ttevent_common_threaded_activate_immediate(ev);\\n\\t}\\n#endif/s" \
        "$SAMBA4_SRC_DIR/lib/tevent/tevent_epoll.c"
    perl -0pi -e "s/\\n\\tif \\(ev->threaded_contexts != NULL\\) \\{\\n\\t\\ttevent_common_threaded_activate_immediate\\(ev\\);\\n\\t\\}/\\n#ifdef HAVE_PTHREAD\\n\\tif (ev->threaded_contexts != NULL) {\\n\\t\\ttevent_common_threaded_activate_immediate(ev);\\n\\t}\\n#endif/s" \
        "$SAMBA4_SRC_DIR/lib/tevent/tevent_port.c"

    perl -0pi -e 's/sizeret = SMB_VFS_LISTXATTR\(conn,\n\s+smb_fname,\n\s+ea_namelist,\n\s+ea_namelist_size\);\n/sizeret = SMB_VFS_LISTXATTR(conn,\n\t\t\t\t    smb_fname,\n\t\t\t\t    ea_namelist,\n\t\t\t\t    ea_namelist_size);\n\tDEBUG(0, ("get_ea_names_from_file: initial listxattr path=%s sizeret=%zd errno=%d\\n",\n\t\t   smb_fname_str_dbg(smb_fname),\n\t\t   sizeret,\n\t\t   errno));\n/s' \
        "$SAMBA4_SRC_DIR/source3/smbd/trans2.c"
    perl -0pi -e 's/sizeret = SMB_VFS_LISTXATTR\(conn,\n\s+smb_fname,\n\s+ea_namelist,\n\s+ea_namelist_size\);\n\t\t}\n/sizeret = SMB_VFS_LISTXATTR(conn,\n\t\t\t\t    smb_fname,\n\t\t\t\t    ea_namelist,\n\t\t\t\t    ea_namelist_size);\n\t\t}\n\t\tDEBUG(0, ("get_ea_names_from_file: retry listxattr path=%s sizeret=%zd errno=%d\\n",\n\t\t\t   smb_fname_str_dbg(smb_fname),\n\t\t\t   sizeret,\n\t\t\t   errno));\n/s' \
        "$SAMBA4_SRC_DIR/source3/smbd/trans2.c"
    perl -0pi -e 's/for \(p = ea_namelist; p - ea_namelist < sizeret; p \+= strlen\(p\)\+1\) \{\n\t\tnum_names \+= 1;\n\t\}/for (p = ea_namelist; p - ea_namelist < sizeret; p += strlen(p)+1) {\n\t\tDEBUG(0, ("get_ea_names_from_file: raw name=%s path=%s\\n",\n\t\t\t   p,\n\t\t\t   smb_fname_str_dbg(smb_fname)));\n\t\tnum_names += 1;\n\t}/s' \
        "$SAMBA4_SRC_DIR/source3/smbd/trans2.c"

    perl -0pi -e 's/stype = strrchr_m\(sname, ':'\);\n/stype = strrchr_m(sname, ':');\n\tDEBUG(0, ("streams_xattr_get_name: stream_name=%s sname=%s stype=%s store_stream_type=%d\\n",\n\t\t   stream_name,\n\t\t   sname,\n\t\t   stype ? stype : "<none>",\n\t\t   (int)config->store_stream_type));\n/s' \
        "$SAMBA4_SRC_DIR/source3/modules/vfs_streams_xattr.c"
    perl -0pi -e 's/if \(strcasecmp_m\(stype, ":\\$DATA"\) != 0\) \{\n\t\t\ttalloc_free\(sname\);\n\t\t\treturn NT_STATUS_INVALID_PARAMETER;\n\t\t\}/if (strcasecmp_m(stype, ":\\$DATA") != 0) {\n\t\t\tDEBUG(0, ("streams_xattr_get_name: rejecting stream_name=%s sname=%s stype=%s\\n",\n\t\t\t\t   stream_name,\n\t\t\t\t   sname,\n\t\t\t\t   stype));\n\t\t\ttalloc_free(sname);\n\t\t\treturn NT_STATUS_INVALID_PARAMETER;\n\t\t}/s' \
        "$SAMBA4_SRC_DIR/source3/modules/vfs_streams_xattr.c"
    perl -0pi -e 's/status = get_ea_names_from_file\(talloc_tos\(\),\n\t\t\thandle->conn,\n\t\t\tfsp,\n\t\t\tsmb_fname,\n\t\t\t&names,\n\t\t\t&num_names\);\n/status = get_ea_names_from_file(talloc_tos(),\n\t\t\thandle->conn,\n\t\t\tfsp,\n\t\t\tsmb_fname,\n\t\t\t&names,\n\t\t\t&num_names);\n\tDEBUG(0, ("walk_xattr_streams: get_ea_names path=%s status=%s num_names=%u\\n",\n\t\t   smb_fname_str_dbg(smb_fname),\n\t\t   nt_errstr(status),\n\t\t   (unsigned int)num_names));\n/s' \
        "$SAMBA4_SRC_DIR/source3/modules/vfs_streams_xattr.c"
    perl -0pi -e 's/for \(i=0; i<num_names; i\+\+\) \{\n\t\tstruct ea_struct ea;\n/for (i=0; i<num_names; i++) {\n\t\tstruct ea_struct ea;\n\t\tDEBUG(0, ("walk_xattr_streams: name[%zu]=%s path=%s\\n",\n\t\t\t   i,\n\t\t\t   names[i],\n\t\t\t   smb_fname_str_dbg(smb_fname)));\n/s' \
        "$SAMBA4_SRC_DIR/source3/modules/vfs_streams_xattr.c"
    perl -0pi -e 's/status = get_ea_value\(names,\n\t\t\t\t\thandle->conn,\n\t\t\t\t\tNULL,\n\t\t\t\t\tsmb_fname,\n\t\t\t\t\tnames\[i\],\n\t\t\t\t\t&ea\);\n/status = get_ea_value(names,\n\t\t\t\t\thandle->conn,\n\t\t\t\t\tNULL,\n\t\t\t\t\tsmb_fname,\n\t\t\t\t\tnames[i],\n\t\t\t\t\t&ea);\n\t\tDEBUG(0, ("walk_xattr_streams: get_ea_value path=%s name=%s status=%s\\n",\n\t\t\t   smb_fname_str_dbg(smb_fname),\n\t\t\t   names[i],\n\t\t\t   nt_errstr(status)));\n/s' \
        "$SAMBA4_SRC_DIR/source3/modules/vfs_streams_xattr.c"
    perl -0pi -e 's/ea.name = talloc_asprintf\(\n\t\t\tea.value.data, ":%s%s",\n\t\t\tnames\[i\] \+ config->prefix_len,\n\t\t\tconfig->store_stream_type \? "" : ":\\$DATA"\);\n/ea.name = talloc_asprintf(\n\t\t\tea.value.data, ":%s%s",\n\t\t\tnames[i] + config->prefix_len,\n\t\t\tconfig->store_stream_type ? "" : ":\\$DATA");\n\t\tDEBUG(0, ("walk_xattr_streams: synthesized stream path=%s name=%s stream=%s\\n",\n\t\t\t   smb_fname_str_dbg(smb_fname),\n\t\t\t   names[i],\n\t\t\t   ea.name ? ea.name : "<null>"));\n/s' \
        "$SAMBA4_SRC_DIR/source3/modules/vfs_streams_xattr.c"
    perl -0pi -e 's/status = walk_xattr_streams\(handle, fsp, smb_fname,\n\t\t\t\t    collect_one_stream, &state\);\n/status = walk_xattr_streams(handle, fsp, smb_fname,\n\t\t\t\t    collect_one_stream, &state);\n\t\tDEBUG(0, ("streams_xattr_streaminfo: after walk path=%s status=%s state_status=%s num_streams=%u\\n",\n\t\t   smb_fname_str_dbg(smb_fname),\n\t\t   nt_errstr(status),\n\t\t   nt_errstr(state.status),\n\t\t   state.num_streams));\n/s' \
        "$SAMBA4_SRC_DIR/source3/modules/vfs_streams_xattr.c"
    perl -0pi -e 's/status = walk_xattr_streams\(handle, fsp, smb_fname,\n\t\t\t\t    collect_one_stream, &state\);/\t\tDEBUG(0, ("streams_xattr_streaminfo: enter path=%s current_num=%u\\n",\n\t\t   smb_fname_str_dbg(smb_fname),\n\t\t   *pnum_streams));\n\t\tstatus = walk_xattr_streams(handle, fsp, smb_fname,\n\t\t\t\t    collect_one_stream, &state);/s' \
        "$SAMBA4_SRC_DIR/source3/modules/vfs_streams_xattr.c"

    ${PYTHON:-python2.7} - "$SAMBA4_SRC_DIR/source3/modules/vfs_xattr_tdb.c" <<'PY'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    data = f.read()

def patch_once(old, new, label):
    global data
    if old not in data:
        raise SystemExit("patch not found for %s" % label)
    data = data.replace(old, new, 1)

patch_once(
"""	ret = xattr_tdb_get_file_id(handle, smb_fname->base_name, &id);
	if (ret == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	xattr_size = xattr_tdb_getattr(db, frame, &id, name, &blob);
""",
"""	DEBUG(0, ("xattr_tdb_getxattr: path=%s name=%s size=%zu\\n",
	   smb_fname_str_dbg(smb_fname),
	   name,
	   size));
	ret = xattr_tdb_get_file_id(handle, smb_fname->base_name, &id);
	if (ret == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	xattr_size = xattr_tdb_getattr(db, frame, &id, name, &blob);
	DEBUG(0, ("xattr_tdb_getxattr: getattr path=%s name=%s ret=%zd errno=%d blob_len=%zu\\n",
	   smb_fname_str_dbg(smb_fname),
	   name,
	   xattr_size,
	   errno,
	   (size_t)blob.length));
""",
"xattr_tdb_getxattr")

patch_once(
"""	if (SMB_VFS_NEXT_FSTAT(handle, fsp, &sbuf) == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	id = SMB_VFS_NEXT_FILE_ID_CREATE(handle, &sbuf);

	xattr_size = xattr_tdb_getattr(db, frame, &id, name, &blob);
""",
"""	DEBUG(0, ("xattr_tdb_fgetxattr: fsp=%s name=%s size=%zu\\n",
	   fsp_str_dbg(fsp),
	   name,
	   size));
	if (SMB_VFS_NEXT_FSTAT(handle, fsp, &sbuf) == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	id = SMB_VFS_NEXT_FILE_ID_CREATE(handle, &sbuf);

	xattr_size = xattr_tdb_getattr(db, frame, &id, name, &blob);
	DEBUG(0, ("xattr_tdb_fgetxattr: getattr fsp=%s name=%s ret=%zd errno=%d blob_len=%zu\\n",
	   fsp_str_dbg(fsp),
	   name,
	   xattr_size,
	   errno,
	   (size_t)blob.length));
""",
"xattr_tdb_fgetxattr")

patch_once(
"""	ret = xattr_tdb_get_file_id(handle, smb_fname->base_name, &id);
	if (ret == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	ret = xattr_tdb_setattr(db, &id, name, value, size, flags);
""",
"""	DEBUG(0, ("xattr_tdb_setxattr: path=%s name=%s size=%zu flags=%d\\n",
	   smb_fname_str_dbg(smb_fname),
	   name,
	   size,
	   flags));
	ret = xattr_tdb_get_file_id(handle, smb_fname->base_name, &id);
	if (ret == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	ret = xattr_tdb_setattr(db, &id, name, value, size, flags);
	DEBUG(0, ("xattr_tdb_setxattr: setattr path=%s name=%s ret=%d errno=%d\\n",
	   smb_fname_str_dbg(smb_fname),
	   name,
	   ret,
	   errno));
""",
"xattr_tdb_setxattr")

patch_once(
"""	if (SMB_VFS_NEXT_FSTAT(handle, fsp, &sbuf) == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	id = SMB_VFS_NEXT_FILE_ID_CREATE(handle, &sbuf);

	ret = xattr_tdb_setattr(db, &id, name, value, size, flags);
""",
"""	DEBUG(0, ("xattr_tdb_fsetxattr: fsp=%s name=%s size=%zu flags=%d\\n",
	   fsp_str_dbg(fsp),
	   name,
	   size,
	   flags));
	if (SMB_VFS_NEXT_FSTAT(handle, fsp, &sbuf) == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	id = SMB_VFS_NEXT_FILE_ID_CREATE(handle, &sbuf);

	ret = xattr_tdb_setattr(db, &id, name, value, size, flags);
	DEBUG(0, ("xattr_tdb_fsetxattr: setattr fsp=%s name=%s ret=%d errno=%d\\n",
	   fsp_str_dbg(fsp),
	   name,
	   ret,
	   errno));
""",
"xattr_tdb_fsetxattr")

patch_once(
"""	ret = xattr_tdb_get_file_id(handle, smb_fname->base_name, &id);
	if (ret == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	ret = xattr_tdb_listattr(db, &id, list, size);
""",
"""	DEBUG(0, ("xattr_tdb_listxattr: path=%s size=%zu\\n",
	   smb_fname_str_dbg(smb_fname),
	   size));
	ret = xattr_tdb_get_file_id(handle, smb_fname->base_name, &id);
	if (ret == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	ret = xattr_tdb_listattr(db, &id, list, size);
	DEBUG(0, ("xattr_tdb_listxattr: listattr path=%s ret=%d errno=%d\\n",
	   smb_fname_str_dbg(smb_fname),
	   ret,
	   errno));
""",
"xattr_tdb_listxattr")

patch_once(
"""	if (SMB_VFS_NEXT_FSTAT(handle, fsp, &sbuf) == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	id = SMB_VFS_NEXT_FILE_ID_CREATE(handle, &sbuf);

	ret = xattr_tdb_listattr(db, &id, list, size);
""",
"""	DEBUG(0, ("xattr_tdb_flistxattr: fsp=%s size=%zu\\n",
	   fsp_str_dbg(fsp),
	   size));
	if (SMB_VFS_NEXT_FSTAT(handle, fsp, &sbuf) == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	id = SMB_VFS_NEXT_FILE_ID_CREATE(handle, &sbuf);

	ret = xattr_tdb_listattr(db, &id, list, size);
	DEBUG(0, ("xattr_tdb_flistxattr: listattr fsp=%s ret=%d errno=%d\\n",
	   fsp_str_dbg(fsp),
	   ret,
	   errno));
""",
"xattr_tdb_flistxattr")

patch_once(
"""	ret = xattr_tdb_get_file_id(handle, smb_fname->base_name, &id);
	if (ret == -1) {
		TALLOC_FREE(frame);
		return ret;
	}

	
	ret = xattr_tdb_removeattr(db, &id, name);
""",
"""	DEBUG(0, ("xattr_tdb_removexattr: path=%s name=%s\\n",
	   smb_fname_str_dbg(smb_fname),
	   name));
	ret = xattr_tdb_get_file_id(handle, smb_fname->base_name, &id);
	if (ret == -1) {
		TALLOC_FREE(frame);
		return ret;
	}

	ret = xattr_tdb_removeattr(db, &id, name);
	DEBUG(0, ("xattr_tdb_removexattr: removeattr path=%s name=%s ret=%d errno=%d\\n",
	   smb_fname_str_dbg(smb_fname),
	   name,
	   ret,
	   errno));
""",
"xattr_tdb_removexattr")

patch_once(
"""	if (SMB_VFS_NEXT_FSTAT(handle, fsp, &sbuf) == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	id = SMB_VFS_NEXT_FILE_ID_CREATE(handle, &sbuf);

	ret = xattr_tdb_removeattr(db, &id, name);
""",
"""	DEBUG(0, ("xattr_tdb_fremovexattr: fsp=%s name=%s\\n",
	   fsp_str_dbg(fsp),
	   name));
	if (SMB_VFS_NEXT_FSTAT(handle, fsp, &sbuf) == -1) {
		TALLOC_FREE(frame);
		return -1;
	}

	id = SMB_VFS_NEXT_FILE_ID_CREATE(handle, &sbuf);

	ret = xattr_tdb_removeattr(db, &id, name);
	DEBUG(0, ("xattr_tdb_fremovexattr: removeattr fsp=%s name=%s ret=%d errno=%d\\n",
	   fsp_str_dbg(fsp),
	   name,
	   ret,
	   errno));
""",
"xattr_tdb_fremovexattr")

patch_once(
"""	become_root();
	db = db_open(NULL, dbname, 0, TDB_DEFAULT, O_RDWR|O_CREAT, 0600,
		     DBWRAP_LOCK_ORDER_2, DBWRAP_FLAG_NONE);
	unbecome_root();
""",
"""	become_root();
	db = db_open(NULL, dbname, 0, TDB_DEFAULT, O_RDWR|O_CREAT, 0600,
		     DBWRAP_LOCK_ORDER_2, DBWRAP_FLAG_NONE);
	DEBUG(0, ("xattr_tdb_init: snum=%d dbname=%s db=%p errno=%d\\n",
	   snum,
	   dbname,
	   db,
	   errno));
	unbecome_root();
""",
"xattr_tdb_init")

with open(path, 'w') as f:
    f.write(data)
PY

    ${PYTHON:-python2.7} - "$SAMBA4_SRC_DIR/source3/lib/xattr_tdb.c" <<'PY'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    data = f.read()

def patch_once(old, new, label):
    global data
    if old not in data:
        raise SystemExit("patch not found for %s" % label)
    data = data.replace(old, new, 1)

patch_once(
"""	if (data->dsize == 0) {
		*presult = result;
		return NT_STATUS_OK;
	}

	blob = data_blob_const(data->dptr, data->dsize);
""",
"""	DEBUG(0, ("xattr_tdb_pull_attrs: dsize=%u\\n",
	   (unsigned int)data->dsize));
	if (data->dsize == 0) {
		DEBUG(0, ("xattr_tdb_pull_attrs: empty record\\n"));
		*presult = result;
		return NT_STATUS_OK;
	}

	blob = data_blob_const(data->dptr, data->dsize);
	DEBUG(0, ("xattr_tdb_pull_attrs: blob length=%u\\n",
	   (unsigned int)blob.length));
""",
"xattr_tdb_pull_attrs_start")

patch_once(
"""	if (!NDR_ERR_CODE_IS_SUCCESS(ndr_err)) {
		DEBUG(0, ("ndr_pull_tdb_xattrs failed: %s\\n",
			  ndr_errstr(ndr_err)));
		TALLOC_FREE(result);
		return ndr_map_error2ntstatus(ndr_err);
	}

	*presult = result;
	return NT_STATUS_OK;
""",
"""	if (!NDR_ERR_CODE_IS_SUCCESS(ndr_err)) {
		DEBUG(0, ("ndr_pull_tdb_xattrs failed: %s\\n",
			  ndr_errstr(ndr_err)));
		TALLOC_FREE(result);
		return ndr_map_error2ntstatus(ndr_err);
	}

	DEBUG(0, ("xattr_tdb_pull_attrs: parsed num_eas=%u\\n",
	   (unsigned int)result->num_eas));
	*presult = result;
	return NT_STATUS_OK;
""",
"xattr_tdb_pull_attrs_end")

patch_once(
"""	ndr_err = ndr_push_struct_blob(&blob, mem_ctx, attribs,
		(ndr_push_flags_fn_t)ndr_push_tdb_xattrs);
""",
"""	DEBUG(0, ("xattr_tdb_push_attrs: num_eas=%u\\n",
	   (unsigned int)attribs->num_eas));
	ndr_err = ndr_push_struct_blob(&blob, mem_ctx, attribs,
		(ndr_push_flags_fn_t)ndr_push_tdb_xattrs);
""",
"xattr_tdb_push_attrs_start")

patch_once(
"""	*data = make_tdb_data(blob.data, blob.length);
	return NT_STATUS_OK;
""",
"""	*data = make_tdb_data(blob.data, blob.length);
	DEBUG(0, ("xattr_tdb_push_attrs: serialized size=%u\\n",
	   (unsigned int)blob.length));
	return NT_STATUS_OK;
""",
"xattr_tdb_push_attrs_end")

patch_once(
"""	/* For backwards compatibility only store the dev/inode. */
	push_file_id_16((char *)id_buf, id);

	status = dbwrap_fetch(db_ctx, mem_ctx,
			      make_tdb_data(id_buf, sizeof(id_buf)),
			      &data);
	if (!NT_STATUS_IS_OK(status)) {
		return NT_STATUS_INTERNAL_DB_CORRUPTION;
	}

	status = xattr_tdb_pull_attrs(mem_ctx, &data, presult);
""",
"""	/* For backwards compatibility only store the dev/inode. */
	push_file_id_16((char *)id_buf, id);
	DEBUG(0, ("xattr_tdb_load_attrs: id=%s key=%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x\\n",
	   file_id_string(mem_ctx, id),
	   id_buf[0], id_buf[1], id_buf[2], id_buf[3],
	   id_buf[4], id_buf[5], id_buf[6], id_buf[7],
	   id_buf[8], id_buf[9], id_buf[10], id_buf[11],
	   id_buf[12], id_buf[13], id_buf[14], id_buf[15]));

	status = dbwrap_fetch(db_ctx, mem_ctx,
			      make_tdb_data(id_buf, sizeof(id_buf)),
			      &data);
	DEBUG(0, ("xattr_tdb_load_attrs: fetch status=%s dsize=%u\\n",
	   nt_errstr(status),
	   (unsigned int)data.dsize));
	if (NT_STATUS_EQUAL(status, NT_STATUS_NOT_FOUND)) {
		struct tdb_xattrs *empty = talloc_zero(mem_ctx, struct tdb_xattrs);
		DEBUG(0, ("xattr_tdb_load_attrs: treating NOT_FOUND as empty attrs for id=%s\\n",
		   file_id_string(mem_ctx, id)));
		if (empty == NULL) {
			return NT_STATUS_NO_MEMORY;
		}
		*presult = empty;
		return NT_STATUS_OK;
	}
	if (!NT_STATUS_IS_OK(status)) {
		return NT_STATUS_INTERNAL_DB_CORRUPTION;
	}

	status = xattr_tdb_pull_attrs(mem_ctx, &data, presult);
	DEBUG(0, ("xattr_tdb_load_attrs: pull status=%s\\n",
	   nt_errstr(status)));
""",
"xattr_tdb_load_attrs")

patch_once(
"""	status = xattr_tdb_load_attrs(frame, db_ctx, id, &attribs);

	if (!NT_STATUS_IS_OK(status)) {
		DEBUG(10, ("xattr_tdb_fetch_attrs failed: %s\\n",
			   nt_errstr(status)));
		TALLOC_FREE(frame);
		errno = EINVAL;
		return -1;
	}

	for (i=0; i<attribs->num_eas; i++) {
""",
"""	status = xattr_tdb_load_attrs(frame, db_ctx, id, &attribs);

	if (!NT_STATUS_IS_OK(status)) {
		DEBUG(10, ("xattr_tdb_fetch_attrs failed: %s\\n",
			   nt_errstr(status)));
		TALLOC_FREE(frame);
		errno = EINVAL;
		return -1;
	}

	DEBUG(0, ("xattr_tdb_getattr: loaded num_eas=%u for id=%s\\n",
	   (unsigned int)attribs->num_eas,
	   file_id_string(frame, id)));
	for (i=0; i<attribs->num_eas; i++) {
		DEBUG(0, ("xattr_tdb_getattr: ea[%u] name=%s len=%u\\n",
		   (unsigned int)i,
		   attribs->eas[i].name,
		   (unsigned int)attribs->eas[i].value.length));
""",
"xattr_tdb_getattr_loop")

patch_once(
"""	if (i == attribs->num_eas) {
		errno = ENOATTR;
		goto fail;
	}

	*blob = attribs->eas[i].value;
""",
"""	if (i == attribs->num_eas) {
		DEBUG(0, ("xattr_tdb_getattr: name=%s not found id=%s\\n",
		   name,
		   file_id_string(frame, id)));
		errno = ENOATTR;
		goto fail;
	}

	DEBUG(0, ("xattr_tdb_getattr: found name=%s idx=%u len=%u\\n",
	   name,
	   (unsigned int)i,
	   (unsigned int)attribs->eas[i].value.length));
	*blob = attribs->eas[i].value;
""",
"xattr_tdb_getattr_found")

patch_once(
"""	status = xattr_tdb_load_attrs(frame, db_ctx, id, &attribs);

	if (!NT_STATUS_IS_OK(status)) {
		DEBUG(10, ("xattr_tdb_fetch_attrs failed: %s\\n",
			   nt_errstr(status)));
		errno = EINVAL;
		TALLOC_FREE(frame);
		return -1;
	}

	DEBUG(10, ("xattr_tdb_listattr: Found %d xattrs\\n",
		   attribs->num_eas));

	for (i=0; i<attribs->num_eas; i++) {
""",
"""	status = xattr_tdb_load_attrs(frame, db_ctx, id, &attribs);

	if (!NT_STATUS_IS_OK(status)) {
		DEBUG(10, ("xattr_tdb_fetch_attrs failed: %s\\n",
			   nt_errstr(status)));
		errno = EINVAL;
		TALLOC_FREE(frame);
		return -1;
	}

	DEBUG(0, ("xattr_tdb_listattr: id=%s found num_eas=%u size=%zu\\n",
	   file_id_string(frame, id),
	   (unsigned int)attribs->num_eas,
	   size));
	DEBUG(10, ("xattr_tdb_listattr: Found %d xattrs\\n",
		   attribs->num_eas));

	for (i=0; i<attribs->num_eas; i++) {
""",
"xattr_tdb_listattr_loop")

patch_once(
"""	if (len > size) {
		TALLOC_FREE(frame);
		errno = ERANGE;
		return len;
	}

	len = 0;
""",
"""	if (len > size) {
		DEBUG(0, ("xattr_tdb_listattr: required len=%zu exceeds size=%zu\\n",
		   len,
		   size));
		TALLOC_FREE(frame);
		errno = ERANGE;
		return len;
	}

	DEBUG(0, ("xattr_tdb_listattr: total len=%zu writing list\\n", len));
	len = 0;
""",
"xattr_tdb_listattr_size")

patch_once(
"""	TALLOC_FREE(frame);
	return len;
}
""",
"""	DEBUG(0, ("xattr_tdb_listattr: final len=%zu\\n", len));
	TALLOC_FREE(frame);
	return len;
}
""",
"xattr_tdb_listattr_end")

with open(path, 'w') as f:
    f.write(data)
PY

    git -C "$SAMBA4_SRC_DIR" rev-parse --short HEAD
    git -C "$SAMBA4_SRC_DIR" log -1 --format='%H%n%cd%n%s' --date=iso
    echo "Finished Samba 4 download workflow at $(date -u)"
} >"$SAMBA4_DOWNLOAD_LOG" 2>&1

printf 'Samba 4 download complete.\n'
printf 'Log: %s\n' "$SAMBA4_DOWNLOAD_LOG"
