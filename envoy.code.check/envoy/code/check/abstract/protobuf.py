
import json
import pathlib
from functools import cached_property

from google.protobuf import descriptor_pb2
from google.protobuf import descriptor_pool as _descriptor_pool
from google.protobuf import json_format
from google.protobuf import message_factory

import yaml as _yaml


class IgnoredKey(_yaml.YAMLObject):
    """Python support type for Envoy's config !ignore tag."""
    yaml_tag = '!ignore'

    def __init__(self, strval):
        self.strval = strval

    def __repr__(self):
        return f'IgnoredKey({str})'

    def __eq__(self, other):
        return isinstance(other, IgnoredKey) and self.strval == other.strval

    def __hash__(self):
        return hash((self.yaml_tag, self.strval))

    @classmethod
    def from_yaml(cls, loader, node):
        return IgnoredKey(node.value)

    @classmethod
    def to_yaml(cls, dumper, data):
        return dumper.represent_scalar(cls.yaml_tag, data.strval)


class AProtobuf:

    def __init__(self, descriptor_path):
        self._descriptor_path = descriptor_path

    @cached_property
    def descriptor(self):
        descriptor = descriptor_pb2.FileDescriptorSet()
        descriptor.ParseFromString(self.descriptor_path.read_bytes())
        return descriptor

    @cached_property
    def descriptor_path(self):
        return pathlib.Path(self._descriptor_path)

    @cached_property
    def descriptor_pool(self):
        pool = _descriptor_pool.DescriptorPool()
        for f in self.descriptor.file:
            pool.Add(f)
        return pool

    @cached_property
    def yaml(self):
        _yaml.SafeLoader.add_constructor('!ignore', IgnoredKey.from_yaml)
        _yaml.SafeDumper.add_multi_representer(IgnoredKey, IgnoredKey.to_yaml)
        return _yaml

    def validate_fragment(self, type_name, fragment):
        """Validate a dictionary representing a JSON/YAML fragment against an Envoy API proto3 type.

        Throws Protobuf errors on parsing exceptions, successful validations produce
        no result.
        """
        json_fragment = json.dumps(fragment, skipkeys=True)
        desc = self.descriptor_pool.FindMessageTypeByName(type_name)
        msg = message_factory.MessageFactory(pool=self.descriptor_pool).GetPrototype(desc)()
        result = json_format.Parse(json_fragment, msg, descriptor_pool=self.descriptor_pool)

    def validate_yaml(self, fragment, type_name="envoy.config.bootstrap.v3.Bootstrap"):
        self.validate_fragment(type_name, self.yaml.safe_load(fragment))
