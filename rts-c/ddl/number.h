#ifndef DDL_NUMBER_H
#define DDL_NUMBER_H

#include <cstdint>
#include <cassert>
#include <type_traits>
#include <iostream>
#include <ios>
#include <cmath>

#include <ddl/value.h>
#include <ddl/bool.h>
#include <ddl/size.h>


namespace DDL {


// Unsigned --------------------------------------------------------------------

template <Width w>
class UInt : public Value {
  static_assert(w <= 64, "UInt larger than 64 not supported.");

public:
  using Rep =
    typename std::conditional < (w <= 8),   uint8_t,
    typename std::conditional < (w <= 16),  uint16_t,
    typename std::conditional < (w <= 32),  uint32_t,
                                            uint64_t
    >::type>::type>::type;

  static constexpr Width bitWidth = w;

private:
  Rep data;

public:

  // For uninitialized values
  UInt() : data(0) {}

  // For literals and casts
  UInt(unsigned x)           : data(static_cast<Rep>(x)) {}
  UInt(unsigned long x)      : data(static_cast<Rep>(x)) {}
  UInt(unsigned long long x) : data(static_cast<Rep>(x)) {}

  UInt(int x)                : data(static_cast<Rep>(x)) {}
  UInt(long x)               : data(static_cast<Rep>(x)) {}
  UInt(long long x)          : data(static_cast<Rep>(x)) {}

  UInt(float x)              : data(static_cast<Rep>(x)) {}
  UInt(double x)             : data(static_cast<Rep>(x)) {}


  // Shouldn't really be used by client code.
  Rep rawRep() const { return data; }

  // This is for `a # b`
  template <Width a, Width b>
  UInt(UInt<a> x, UInt<b> y) : data((Rep{x.rawRep()} << b) | y.rep()) {
    static_assert(a + b == w);
  }

  Rep rep() const {
    if constexpr (w == 8 || w == 16 || w == 32 || w == 64) return data;
    if constexpr (w < 8)   return data & (UINT8_MAX  >> ( 8-w));
    if constexpr (w < 16)  return data & (UINT16_MAX >> (16-w));
    if constexpr (w < 32)  return data & (UINT32_MAX >> (32-w));
    return                        data & (UINT64_MAX >> (64-w));
  }


  constexpr static Rep maxValRep() {
    if constexpr (w ==  8) return UINT8_MAX;  else
    if constexpr (w == 16) return UINT16_MAX; else
    if constexpr (w == 32) return UINT32_MAX; else
    if constexpr (w == 64) return UINT64_MAX; else
    return (1 << w) - 1;
  }


  UInt operator + (UInt x) const { return UInt(data + x.data); }
  UInt operator - (UInt x) const { return UInt(data - x.data); }
  UInt operator * (UInt x) const { return UInt(data * x.data); }
  UInt operator % (UInt x) const { Rep xv = x.rep();
                                   assert(xv != 0);
                                   return UInt(rep() % xv); }
  UInt operator / (UInt x) const { Rep xv = x.rep();
                                   assert(xv != 0);
                                   return UInt(rep() / xv); }
  UInt operator - ()       const { return UInt(-data); }
  UInt operator ~ ()       const { return UInt(~data); }

  UInt operator | (UInt x) const { return UInt(data | x.data); }
  UInt operator & (UInt x) const { return UInt(data & x.data); }
  UInt operator ^ (UInt x) const { return UInt(data ^ x.data); }

  // XXX: remove in favor of Size
  UInt operator << (UInt<64> x) const { return UInt(data << x.rep()); }
  UInt operator >> (UInt<64> x) const { return UInt(data >> x.rep()); }

  // Assumes C++ 20 semantics
  UInt operator << (Size x) const { return UInt(data << x.rep()); }
  UInt operator >> (Size x) const { return UInt(data >> x.rep()); }

  bool operator == (UInt x) const { return rep() == x.rep(); }
  bool operator != (UInt x) const { return rep() != x.rep(); }
  bool operator <  (UInt x) const { return rep() <  x.rep(); }
  bool operator <= (UInt x) const { return rep() <= x.rep(); }
  bool operator >  (UInt x) const { return rep() >  x.rep(); }
  bool operator >= (UInt x) const { return rep() >= x.rep(); }

  Size asSize() const { return Size::from(rep()); }  // used in array

  // Bitdata
  UInt toBits()                { return *this; }
  static UInt fromBits(UInt x) { return x; }
  static bool isValid(UInt x)  { return true; }
};


template <Width a, Width b>
static inline
UInt<a> lcat(UInt<a> x, UInt<b> y) {
  if constexpr (b >= a) return UInt<a>(y.data);
  return UInt<a>((x.rawRep() << b) | y.rep());
}

template <Width w>
static inline
int compare(UInt<w> x, UInt<w> y) {
  auto rx = x.rep();
  auto ry = y.rep();
  return (rx < ry) ? -1 : (rx != ry);
}


template <Width w>
static inline
std::ostream& operator<<(std::ostream& os, UInt<w> x) {
  os << static_cast<uint64_t>(x.rep());
  return os;
}


template <Width w>
static inline
std::ostream& toJS(std::ostream& os, UInt<w> x) {
  return os << static_cast<uint64_t>(x.rep());
}





// Signed ----------------------------------------------------------------------


// XXX: How should arithmetic work on these?
// For the moment we assume no under/overflow, same as C does
// but it is not clear if that's what we want from daedluas.
// XXX: Add `asserts` to detect wrap around in debug mode
template <Width w>
class SInt : public Value {
  static_assert(w >= 1,  "SInt needs at least 1 bit");
  static_assert(w <= 64, "SInt larger than 64 not supported.");

public:

  static constexpr Width bitWidth = w;

  using Rep =
    typename std::conditional < (w <= 8),   int8_t,
    typename std::conditional < (w <= 16),  int16_t,
    typename std::conditional < (w <= 32),  int32_t,
                                            int64_t
    >::type>::type>::type;

private:
  Rep data;

  void fixUp() {
    constexpr size_t extra = 8 * sizeof(Rep) - w;
    if constexpr (extra > 0) {
      Rep x = data << extra;
      data  = x >> extra;
    }
  }

public:
  SInt()      : data(0) {}

  // These are supposed to be total, i.e. defined for all inputs.
  SInt(uint8_t x)  : data(static_cast<Rep>(x)) { if constexpr (w < 8)  fixUp();}
  SInt(uint16_t x) : data(static_cast<Rep>(x)) { if constexpr (w < 16) fixUp();}
  SInt(uint32_t x) : data(static_cast<Rep>(x)) { if constexpr (w < 32) fixUp();}
  SInt(uint64_t x) : data(static_cast<Rep>(x)) { if constexpr (w < 64) fixUp();}

  // These are supposed to be total, i.e. defined for all inputs.
  SInt(int8_t x)  : data(static_cast<Rep>(x)) { if constexpr (w < 8)  fixUp(); }
  SInt(int16_t x) : data(static_cast<Rep>(x)) { if constexpr (w < 16) fixUp(); }
  SInt(int32_t x) : data(static_cast<Rep>(x)) { if constexpr (w < 32) fixUp(); }
  SInt(int64_t x) : data(static_cast<Rep>(x)) { if constexpr (w < 64) fixUp(); }

  SInt(float x)   : data(static_cast<Rep>(x)) { fixUp(); }
  SInt(double x)  : data(static_cast<Rep>(x)) { fixUp(); }

  Rep rep() const { return data; }

  // These are assumed to stay in bounds.
  // XXX: if we used fixUp, would that give us the normal module arithmetic?
  SInt operator + (SInt x) const { return Rep(data + x.data); }
  SInt operator - (SInt x) const { return Rep(data - x.data); }
  SInt operator * (SInt x) const { return Rep(data * x.data); }
  SInt operator % (SInt x) const { return Rep(data % x.data); }
  SInt operator / (SInt x) const { return Rep(data / x.data); }
  SInt operator - ()       const { return Rep(-data); }

  bool operator == (SInt<w> x) const { return rep() == x.rep(); }
  bool operator != (SInt<w> x) const { return rep() != x.rep(); }
  bool operator <  (SInt<w> x) const { return rep() <  x.rep(); }
  bool operator >  (SInt<w> x) const { return rep() >  x.rep(); }
  bool operator <= (SInt<w> x) const { return rep() <= x.rep(); }
  bool operator >= (SInt<w> x) const { return rep() >= x.rep(); }

  constexpr static Rep maxValRep() {
    if constexpr (w ==  8) return INT8_MAX;  else
    if constexpr (w == 16) return INT16_MAX; else
    if constexpr (w == 32) return INT32_MAX; else
    if constexpr (w == 64) return INT64_MAX; else
    return (1 << (w-1)) - 1;
  }

  constexpr static Rep minValRep() {
    return (-maxValRep())-1;
  }
  // XXX: Remove in favor of Size
  SInt operator << (UInt<64> x) const { return SInt(data << x.rep()); }
  SInt operator >> (UInt<64> x) const { return SInt(data >> x.rep()); }

  // Assumes C++ 20 semantics
  // XXX: should we call fixUp or assumed that we are stying in bounds?
  SInt operator << (Size x) const { return SInt(data << x.rep()); }
  SInt operator >> (Size x) const { return SInt(data >> x.rep()); }

  Size asSize() const { return Size::from(rep()); } // used in array

  // Bitdata
  UInt<w> toBits()                { return UInt<w>(data); }
  static SInt fromBits(UInt<w> x) { return SInt(x.rep()); }
  static bool isValid(UInt<w> x)  { return true; }

};


template <Width w>
static inline
int compare(SInt<w> x, SInt<w> y) {
  auto rx = x.rep();
  auto ry = y.rep();
  return (rx < ry) ? -1 : (rx != ry);
}


template <Width a, Width b>
static inline
SInt<a> lcat(SInt<a> x, UInt<b> y) {
  if constexpr (b >= a) return SInt(y.rep());
  else                  return (x << b) | y.rep();
}


template <Width w>
static inline
std::ostream& operator<<(std::ostream& os, SInt<w> x) {
  os << std::dec;
  return os << static_cast<int64_t>(x.rep());
}

template <Width w>
static inline
std::ostream& toJS(std::ostream& os, SInt<w> x) {
  os << std::dec;
  return os << static_cast<int64_t>(x.rep());
}


} // namespace DDL

#endif

