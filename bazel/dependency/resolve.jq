def error_result($message): {error: $message};

def nonempty_or_null($value):
  if ($value | type) == "string" and ($value | length) > 0 then $value else null end;

.dep as $dep
| .allow_yanked as $allow_yanked
| .report_entry as $entry
| if $entry == null then
    error_result("Dependency \($dep) not found in report")
  else
    ($entry.registries | keys) as $available
    | (nonempty_or_null(.requested_registry)) as $requested_registry
    | (nonempty_or_null(.requested_version)) as $requested_version
    | (
        if $requested_registry != null then
          $requested_registry
        elif $requested_version != null then
          ($available | map(select((($entry.registries[.].versions // []) | index($requested_version)) != null))) as $matches
          | if ($entry.current_registry != null and ($matches | index($entry.current_registry)) != null) then
              $entry.current_registry
            elif ($matches | length) == 1 then
              $matches[0]
            elif ($matches | length) == 0 then
              error_result("Version \($requested_version) for \($dep) is not published on any configured registry")
            else
              error_result("Version \($requested_version) is available in multiple registries; pass --registry")
            end
        elif $entry.current_registry != null then
          $entry.current_registry
        elif ($available | length) == 1 then
          $available[0]
        else
          error_result("Unable to determine registry for \($dep); pass --registry")
        end
      ) as $registry
    | if ($registry | type) == "object" then
        $registry
      else
        (($requested_version // ($entry.latest_by_registry[$registry] // ""))) as $target
        | if $target == "" then
            error_result("No non-yanked version found for \($dep) on \($registry)")
          elif ((($entry.registries[$registry].versions // []) | index($target)) == null) then
            error_result("Version \($target) for \($dep) is not published on \($registry)")
          elif (($allow_yanked | not) and ((($entry.registries[$registry].yanked // []) | index($target)) != null)) then
            error_result("Version \($target) for \($dep) is yanked on \($registry); pass --allow-yanked to override")
          else
            {target: $target, registry: $registry}
          end
      end
  end
