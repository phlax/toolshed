
import abstracts

from envoy.code.check import abstract, interface


@abstracts.implementer(interface.IProtobuf)
class Protobuf(abstract.AProtobuf):
    pass
