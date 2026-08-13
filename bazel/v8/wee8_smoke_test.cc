#include "third_party/wasm-api/wasm.hh"

int main() {
  auto config = wasm::Config::make();
  if (config == nullptr) {
    return 1;
  }
  auto engine = wasm::Engine::make(std::move(config));
  if (engine == nullptr) {
    return 1;
  }
  return 0;
}
