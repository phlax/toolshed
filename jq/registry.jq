def unique_preserve:
  reduce .[] as $item ([]; if index($item) == null then . + [$item] else . end);

def capture_value($match; $name):
  $match.captures[] | select(.name == $name);

def attr_match($body; $attr):
  try ($body | match("(?s)\\b" + $attr + "\\s*=\\s*\"(?<value>[^\"]*)\"")) catch null;

def module_name_attr($kind):
  if $kind == "bazel_dep" then "name" else "module_name" end;

def regex_escape:
  explode
  | map([.] | implode)
  | map(
      . as $char
      | if ["\\", "^", "$", ".", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}"] | index($char) then
          "\\" + $char
        else
          $char
        end)
  | join("");

def registry_pattern($url_prefix):
  "(?m)^common --registry="
  + ($url_prefix | regex_escape)
  + "(?<hash>[0-9a-f]+)$";

def registry_path($url_prefix; $hash):
  "common --registry=\($url_prefix)\($hash)";

def bazelrc_hash:
  . as $input
  | reduce ($input.paths // [])[] as $path (null;
      (($input.files[$path] // "") | try capture(registry_pattern($input.url_prefix)).hash catch null) as $hash
      | if $hash == null then
          error("FAIL: failed to determine current registry hash from \($path)")
        elif . != null and . != $hash then
          error("FAIL: registry hash mismatch in \($path): \($hash) != \(.)")
        else
          $hash
        end);

def module_pins:
  . as $input
  | [($input.paths // [])[] as $path
     | ($input.files[$path] // "") as $content
     | [($content | match("(?s)(?<kind>bazel_dep|single_version_override)\\((?<body>.*?)\\)"; "g"))
        | . as $call
        | ($call | capture_value(.; "kind").string) as $kind
        | ($call | capture_value(.; "body")) as $body_capture
        | $body_capture.string as $body
        | attr_match($body; module_name_attr($kind)) as $name_match
        | attr_match($body; "version") as $version_match
        | select($name_match != null and $version_match != null)
        | (capture_value($name_match; "value")) as $name_value
        | (capture_value($version_match; "value")) as $version_value
        | {
            name: $name_value.string,
            version: $version_value.string,
            file: $path,
            kind: $kind,
            version_start: ($body_capture.offset + $version_value.offset),
            version_end: ($body_capture.offset + $version_value.offset + $version_value.length)
          }][]];

def registry_objects:
  reduce .[] as $pin ([];
    . + [
      "modules/\($pin.name)/metadata.json",
      "modules/\($pin.name)/\($pin.version)/MODULE.bazel"
    ])
  | unique_preserve;

def batch_check_exists:
  . as $input
  | ($input.output | split("\n") | map(select(length > 0))) as $lines
  | reduce $lines[] as $line ({};
      if ($line | endswith(" missing")) then
        .[(($line | sub("^" + ($input.hash | regex_escape) + ":"; "") | sub(" missing$"; "")))] = false
      else
        .[(($line | split(" "))[0])] = true
      end);

def ls_remote_hash:
  (. | split("\n") | map(select(length > 0))[0]?) as $line
  | ($line | try capture("^(?<hash>[0-9a-f]+)\\t").hash catch null) as $hash
  | if $hash == null then
      error("FAIL: unable to resolve registry branch")
    else
      $hash
    end;

def normalize_date_token($token):
  if ($token | length) == 8 then $token else "20\($token)" end;

def newest_version:
  if length == 0 then
    error("no replacement versions available")
  else
    ([.[]
      | {version: ., token: (try capture("-(?<token>\\d{8}|\\d{6})(?=[-.]|$)").token catch null)}
      | select(.token != null)
      | .token |= normalize_date_token(.)] as $dated
     | if ($dated | length) > 0 then
         $dated | max_by(.token).version
       else
         .[-1]
       end)
  end;

def module_groups($pins):
  reduce $pins[] as $pin ({};
    .[$pin.name] = ((.[$pin.name] // {name: $pin.name, versions: [], files: [], pins: []})
      | .versions += [$pin.version]
      | .versions |= unique_preserve
      | .files += [$pin.file]
      | .files |= unique_preserve
      | .pins += [$pin]));

def hosted_module($exists; $name):
  $exists["modules/\($name)/metadata.json"] // false;

def hosted_version($exists; $name; $version):
  $exists["modules/\($name)/\($version)/MODULE.bazel"] // false;

def module_change($module_info; $target):
  if ([($module_info.versions[]) == $target] | all) then
    {modules: [], edits: []}
  else
    {
      modules: [{
        name: $module_info.name,
        from: ($module_info.versions | join(", ")),
        to: $target,
        files: $module_info.files
      }],
      edits: [($module_info.pins[] | select(.version != $target)
        | {
            file: .file,
            name: .name,
            from: .version,
            to: $target,
            start: .version_start,
            end: .version_end
          })]
    }
  end;

def metadata_modules:
  . as $input
  | (module_groups($input.pins // [])) as $grouped
  | reduce (($grouped | keys_unsorted[]) // empty) as $name ([];
      ($grouped[$name]) as $module_info
      | if (hosted_module($input.exists; $name)
            and (((($input.overrides // {}) | has($name)))
                 or ([($module_info.versions[] | hosted_version($input.exists; $name; .))] | all | not))) then
          . + [$name]
        else
          .
        end)
  | unique_preserve;

def plan:
  . as $input
  | ($input.overrides // {}) as $overrides
  | (module_groups($input.pins // [])) as $grouped
  | reduce (($grouped | keys) | sort[]) as $name ({
      registry: {old: $input.current_hash, new: $input.target_hash},
      modules: [],
      edits: [],
      errors: [],
      seen_overrides: []
    };
      ($grouped[$name]) as $module_info
      | ($overrides[$name] // null) as $override
      | (hosted_module($input.exists; $name)) as $hosted
      | if $override != null then
          .seen_overrides += [$name]
          | if ($hosted | not) then
              .errors += ["FAIL: --set \($name)=\($override): module is not served by registry \($input.target_hash)"]
            elif ((($input.metadata[$name].versions // []) | index($override)) == null) then
              .errors += ["FAIL: --set \($name)=\($override): version not found in registry \($input.target_hash)"]
            else
              (module_change($module_info; $override)) as $change
              | .modules += $change.modules
              | .edits += $change.edits
            end
        elif ($hosted | not) then
          .
        elif ([($module_info.versions[] | hosted_version($input.exists; $name; .))] | all) then
          .
        else
          (try (($input.metadata[$name].versions // []) | newest_version) catch null) as $replacement
          | if $replacement == null then
              .errors += ["FAIL: \($name)@\($module_info.versions[0]) removed from registry and no replacement versions available"]
            else
              (module_change($module_info; $replacement)) as $change
              | .modules += $change.modules
              | .edits += $change.edits
            end
        end)
  | reduce (($overrides | keys_unsorted[]) // empty) as $name (.;
      if (.seen_overrides | index($name)) != null then
        .
      else
        .errors += ["FAIL: --set \($name)=\($overrides[$name]): module is not pinned in configured MODULE.bazel files"]
      end)
  | del(.seen_overrides);

def apply_hash:
  . as $input
  | reduce ($input.paths // [])[] as $path ({};
      . + {
        ($path): (($input.files[$path] // "")
          | sub(registry_pattern($input.url_prefix); registry_path($input.url_prefix; $input.hash)))
      });

def apply_edits:
  . as $input
  | reduce (($input.edits // []) | sort_by(.file, .start) | reverse[]) as $edit ({};
      .[$edit.file] = (((if has($edit.file) then .[$edit.file] else $input.files[$edit.file] end)
        | .[:$edit.start] + $edit.to + .[$edit.end:])));

def render_report:
  "Registry: \(.registry.old) -> \(.registry.new)\n"
  + "module  from -> to  (files)\n"
  + (if (.modules | length) == 0 then
       "(none)"
     else
       (.modules
        | map((.files | join(", ")) as $files | "\(.name)  \(.from) -> \(.to)  (\($files))")
        | join("\n"))
     end);

def parse_set($value):
  if ($value | test("^[^=]+=.+$")) then
    ($value | capture("^(?<name>[^=]+)=(?<version>.+)$"))
  else
      error("FAIL: --set \($value | @json): expected name=version")
  end;

def parse_args:
  (if type == "array" then . else $ARGS.positional end) as $argv
  | reduce $argv[] as $arg ({hash: null, overrides: {}, pending: null};
      if .pending == "hash" then
        if $arg == "" then
          error("FAIL: --hash requires a value")
        else
          .hash = $arg | .pending = null
        end
      elif .pending == "set" then
        (parse_set($arg)) as $parsed
        | .overrides[$parsed.name] = $parsed.version
        | .pending = null
      elif $arg == "--hash" then
        .pending = "hash"
      elif $arg == "--set" then
        .pending = "set"
      elif ($arg | startswith("--hash=")) then
        ($arg | ltrimstr("--hash=")) as $hash
        | if $hash == "" then error("FAIL: --hash requires a value") else .hash = $hash end
      elif ($arg | startswith("--set=")) then
        (parse_set($arg | ltrimstr("--set="))) as $parsed
        | .overrides[$parsed.name] = $parsed.version
      else
        error("FAIL: unknown arg: \($arg)")
      end)
  | if .pending == "hash" then
      error("FAIL: --hash requires a value")
    elif .pending == "set" then
      error("FAIL: --set requires name=version")
    else
      del(.pending)
    end;
