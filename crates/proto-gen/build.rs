fn main() {
    prost_build::compile_protos(&["../../proto/mrt.proto"], &["../../proto/"]).unwrap();
}
