
import argparse
import json
import sys
import warnings
from functools import cached_property

import abstracts

from aio.api.bazel import interface
from aio.core import pipe, utils
from aio.run import runner


sys.path = [p for p in sys.path if not p.endswith('bazel_tools')]


class ABazelProcessProtocol(
        pipe.AProcessProtocol,
        metaclass=abstracts.Abstraction):

    @cached_property
    def parser(self) -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser(fromfile_prefix_chars='@')
        self.add_arguments(parser)
        return parser

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument("--in")
        parser.add_argument("--out")


class ABazelWorker(runner.Runner, metaclass=abstracts.Abstraction):
    _use_uvloop = False

    @property
    def persistent(self) -> bool:
        return self.args.persistent_worker

    @property  # type:ignore
    @abstracts.interfacemethod
    def processor_class(self):
        raise NotImplementedError

    @cached_property
    def protocol_args(self):
        parser = argparse.ArgumentParser()
        self.protocol_class.add_protocol_arguments(parser)
        return parser.parse_args(self.extra_args)

    @cached_property
    def protocol_class(self):
        return utils.dottedname_resolve(self.args.protocol)

    def add_arguments(self, parser):
        parser.add_argument("protocol")
        parser.add_argument("--persistent_worker", action="store_true")
        super().add_arguments(parser)

    async def protoc_processor(
            self,
            processor: interface.IBazelWorkerProcessor) -> (
                interface.IBazelProcessProtocol):
        return self.protocol_class(processor, self.protocol_args)

    async def run(self) -> None:
        if self.persistent:
            await self.processor_class(self.protoc_processor)()
        # TODO: implement one-shot op


class ABazelWorkerProcessor(
        pipe.StdinStdoutProcessor,
        metaclass=abstracts.Abstraction):

    async def process(self, recv: argparse.Namespace) -> str:
        with warnings.catch_warnings(record=True) as w:
            returned = await (await self.protocol)(recv)
        _warnings = "\n".join(str(warning.message) for warning in w).strip()
        return f"{_warnings}\n{returned or ''}".strip()

    async def recv(self) -> argparse.Namespace:
        return (await self.protocol).parser.parse_args(
            json.loads(
                await self.in_q.get())["arguments"])

    async def send(self, msg) -> None:
        await self.out_q.put(
            json.dumps(dict(exit_code=0, output=msg or "")))
