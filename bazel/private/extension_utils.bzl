"""Shared helpers for module extensions."""

def single_setup_tag(module_ctx, ext_name, repos, attrs):
    tags = [
        tag
        for mod in module_ctx.modules
        for tag in mod.tags.setup
    ]
    if not tags:
        return None
    chosen = tags[0]
    for tag in tags[1:]:
        for attr_name in attrs:
            if getattr(tag, attr_name) == getattr(chosen, attr_name):
                continue
            fail(
                (("Conflicting setup() calls found for %s. " +
                  "Repository names are fixed to %s, so all modules " +
                  "must request identical configuration " +
                  "(differing attribute: %s).") % (ext_name, repos, attr_name)),
            )
    return chosen
