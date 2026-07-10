// Differential cost probes: each loop is the control loop plus one op-chain
// whose result feeds the accumulator through one addition. The marginal cost
// of the op-chain is (probe - control) / n. These are the reproducible
// source of REPORT.md's "Measured Builtin Costs" table, which motivated the
// lane-packed rounds.
use aiken/builtin

const n_iter = 400

const big32 = 4294967295

// ~2^158, realistic magnitude for a 20-byte packed accumulator
const big158 = 365375409332725729550921208179070754913983135744

const pow40 = 1099511627776

const z1 = #"00"

const z16 = #"00000000000000000000000000000000"

fn ctrl(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    ctrl(i - 1, w, acc + i)
  }
}

test probe_ctrl() {
  ctrl(n_iter, #"a1b2c3d4", 0) > 0
}

// truncate32 shape: i2b(5) + slice(1,4) + b2i(4)
fn p_trunc(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    p_trunc(
      i - 1,
      w,
      acc + builtin.bytearray_to_integer(
        True,
        builtin.slice_bytearray(
          1,
          4,
          builtin.integer_to_bytearray(True, 5, big32 + i),
        ),
      ),
    )
  }
}

test probe_trunc() {
  p_trunc(n_iter, #"a1b2c3d4", 0) > 0
}

// i2b(20) + b2i(20) roundtrip on a realistic packed value
fn p_conv20(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    p_conv20(
      i - 1,
      w,
      acc + builtin.bytearray_to_integer(
        True,
        builtin.integer_to_bytearray(True, 20, big158 + i),
      ) % 7,
    )
  }
}

test probe_conv20() {
  p_conv20(n_iter, #"a1b2c3d4", 0) >= 0
}

// full gapped 4-lane pack: 7 concats + b2i(20)
fn p_pack(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    let p0 = builtin.append_bytearray(z1, w)
    let p1 = builtin.append_bytearray(z1, w)
    let p2 = builtin.append_bytearray(z1, w)
    let p3 = builtin.append_bytearray(z1, w)
    let packed = builtin.append_bytearray(
      builtin.append_bytearray(p0, p1),
      builtin.append_bytearray(p2, p3),
    )
    p_pack(i - 1, w, acc + builtin.bytearray_to_integer(True, packed) % 7)
  }
}

test probe_pack() {
  p_pack(n_iter, #"a1b2c3d4", 0) >= 0
}

// 1 concat + b2i(20): isolates concat via (p_pack - p_cat1) / 6
fn p_cat1(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    p_cat1(
      i - 1,
      w,
      acc + builtin.bytearray_to_integer(True, builtin.append_bytearray(z16, w)) % 7,
    )
  }
}

test probe_cat1() {
  p_cat1(n_iter, #"a1b2c3d4", 0) >= 0
}

// message-quad pack: 3 muls by 2^40 + 3 adds
fn p_mpack(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    let x = big32 + i
    p_mpack(i - 1, w, acc + ( ( x * pow40 + x ) * pow40 + x ) * pow40 + x)
  }
}

test probe_mpack() {
  p_mpack(n_iter, #"a1b2c3d4", 0) > 0
}

// b2i(4) alone
fn p_b2i4(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    p_b2i4(i - 1, w, acc + builtin.bytearray_to_integer(True, w))
  }
}

test probe_b2i4() {
  p_b2i4(n_iter, #"a1b2c3d4", 0) > 0
}

// xor(4) + b2i(4)
fn p_xor4(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    p_xor4(
      i - 1,
      w,
      acc + builtin.bytearray_to_integer(
        True,
        builtin.xor_bytearray(False, w, w),
      ),
    )
  }
}

test probe_xor4() {
  p_xor4(n_iter, #"a1b2c3d4", 0) >= 0
}

// rotate(4) + b2i(4)
fn p_rot4(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    p_rot4(
      i - 1,
      w,
      acc + builtin.bytearray_to_integer(True, builtin.rotate_bytearray(w, -12)),
    )
  }
}

test probe_rot4() {
  p_rot4(n_iter, #"a1b2c3d4", 0) > 0
}

// slice(4 of 4) + b2i(4)
fn p_slice4(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    p_slice4(
      i - 1,
      w,
      acc + builtin.bytearray_to_integer(True, builtin.slice_bytearray(0, 4, w)),
    )
  }
}

test probe_slice4() {
  p_slice4(n_iter, #"a1b2c3d4", 0) > 0
}

// i2b(4) + b2i(4)
fn p_i2b4(i: Int, w: ByteArray, acc: Int) -> Int {
  if i == 0 {
    acc
  } else {
    p_i2b4(
      i - 1,
      w,
      acc + builtin.bytearray_to_integer(
        True,
        builtin.integer_to_bytearray(True, 4, big32),
      ),
    )
  }
}

test probe_i2b4() {
  p_i2b4(n_iter, #"a1b2c3d4", 0) > 0
}
