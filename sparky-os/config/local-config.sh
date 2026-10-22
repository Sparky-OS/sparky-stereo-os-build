# Reads the local settings (build.conf.example documents every key) for the bash tools.
# Usage, from a script:  . "$(dirname "$0")/<relative path>/sparky-os/config/local-config.sh"
#                        sparky_need SPARKY_REPO_DIR SPARKY_STAGING_DIR
# A variable already set in the environment wins over the file.
SPARKY_STEREO_CONFIG=${SPARKY_STEREO_CONFIG:-$HOME/.config/sparky-stereo/build.conf}
SPARKY_TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [ -f "$SPARKY_STEREO_CONFIG" ]; then
	while IFS= read -r _sparky_line || [ -n "$_sparky_line" ]; do
		case $_sparky_line in '' | '#'*) continue ;; esac
		_sparky_key=${_sparky_line%%=*}
		case $_sparky_key in *[!A-Za-z0-9_]* | '') continue ;; esac
		[ -n "${!_sparky_key+x}" ] && continue
		_sparky_value=${_sparky_line#*=}
		_sparky_value=${_sparky_value#\"}; _sparky_value=${_sparky_value%\"}
		case $_sparky_value in '~'/*) _sparky_value=$HOME/${_sparky_value#\~/} ;; esac
		eval "export $_sparky_key=\"$_sparky_value\""
	done < "$SPARKY_STEREO_CONFIG"
	unset _sparky_line _sparky_key _sparky_value
fi
if [ -z "${SPARKY_SYNC_TARGET:-}" ] && [ -n "${SPARKY_SYNC_HOST:-}" ] && [ -n "${SPARKY_SYNC_PATH:-}" ]; then
	export SPARKY_SYNC_TARGET="$SPARKY_SYNC_HOST:$SPARKY_SYNC_PATH"
fi
sparky_need() {
	local key
	for key in "$@"; do
		[ -n "${!key:-}" ] || {
			echo "$key is not set: add it to $SPARKY_STEREO_CONFIG (see $SPARKY_TREE/sparky-os/config/build.conf.example)" >&2
			exit 2
		}
	done
}
