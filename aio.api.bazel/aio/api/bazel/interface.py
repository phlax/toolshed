
import abstracts

from aio.core import pipe


class IBazelProcessProtocol(
        pipe.IProcessProtocol,
        metaclass=abstracts.Interface):
    pass


class IBazelWorker(metaclass=abstracts.Interface):
    pass


class IBazelWorkerProcessor(metaclass=abstracts.Interface):
    pass
