GSSAPI="BASE"  # This ensures that a full module is generated by Cython

from gssapi.raw.cython_types cimport *
from gssapi.raw.cython_converters cimport c_make_oid
from gssapi.raw.oids cimport OID

from gssapi.raw._enum_extensions import ExtendableEnum

from enum import IntEnum
import collections
import copy
import numbers
import operator

from collections.abc import MutableSet


class NameType(object):
    # mech-agnostic name types
    hostbased_service = c_make_oid(GSS_C_NT_HOSTBASED_SERVICE)
    # NB(directxman12): skip GSS_C_NT_HOSTBASED_SERVICE_X since it's deprecated
    user = c_make_oid(GSS_C_NT_USER_NAME)
    anonymous = c_make_oid(GSS_C_NT_ANONYMOUS)
    machine_uid = c_make_oid(GSS_C_NT_MACHINE_UID_NAME)
    string_uid = c_make_oid(GSS_C_NT_STRING_UID_NAME)
    export = c_make_oid(GSS_C_NT_EXPORT_NAME)

    # mech-specific name types are added automatically on import


class RequirementFlag(IntEnum, metaclass=ExtendableEnum):
    delegate_to_peer = GSS_C_DELEG_FLAG
    mutual_authentication = GSS_C_MUTUAL_FLAG
    replay_detection = GSS_C_REPLAY_FLAG
    out_of_sequence_detection = GSS_C_SEQUENCE_FLAG
    confidentiality = GSS_C_CONF_FLAG
    integrity = GSS_C_INTEG_FLAG
    anonymity = GSS_C_ANON_FLAG
    protection_ready = GSS_C_PROT_READY_FLAG
    transferable = GSS_C_TRANS_FLAG

    # GSS_C_DELEG_POLICY_FLAG.  cython can't do compile-time detection of
    # this, so take the value from RFC 5896.  Implementations that don't
    # support it will ignore it.
    ok_as_delegate = 32768

    # GSS_C_CHANNEL_BOUND_FLAG, implemented in MIT krb5-1.19
    # See draft-ietf-kitten-channel-bound-flag-04
    channel_bound = 2048


class AddressType(IntEnum, metaclass=ExtendableEnum):
    # unspecified = GSS_C_AF_UNSPEC  # None --> GSS_C_AF_UNSPEC
    local = GSS_C_AF_LOCAL
    ip = GSS_C_AF_INET
    arpanet = GSS_C_AF_IMPLINK  # ARPAnet support, heh, heh
    pup = GSS_C_AF_PUP
    chaos = GSS_C_AF_CHAOS
    xerox_ns = GSS_C_AF_NS  # and XEROX too?
    nbs = GSS_C_AF_NBS
    ecma = GSS_C_AF_ECMA
    datakit = GSS_C_AF_DATAKIT
    ccitt = GSS_C_AF_CCITT
    ibm_sna = GSS_C_AF_SNA
    decnet = GSS_C_AF_DECnet
    dli = GSS_C_AF_DLI
    lat = GSS_C_AF_LAT
    hyperchannel = GSS_C_AF_HYLINK
    appletalk = GSS_C_AF_APPLETALK  # this list just keeps getting better
    bisync = GSS_C_AF_BSC
    dss = GSS_C_AF_DSS
    osi_tp4 = GSS_C_AF_OSI
    x25 = GSS_C_AF_X25
    null = GSS_C_AF_NULLADDR


class MechType(object):
    pass

    # these are added in by the individual mechanism files on import


class GenericFlagSet(MutableSet):

    __slots__ = '_val'
    MAX_VAL = 1 << 31

    def __init__(self, flags=None):
        self._val = 0
        if isinstance(flags, GenericFlagSet):
            self._val = flags._val
        if isinstance(flags, numbers.Integral):
            self._val = int(flags)
        elif flags is not None:
            for flag in flags:
                self._val |= flag

    def __contains__(self, flag):
        return self._val & flag

    def __iter__(self):
        i = 1
        while i < self.MAX_VAL:
            if i & self._val:
                yield i

            i <<= 1

    def __len__(self):
        # get the Hamming weight of _val
        cdef unsigned int size = 0
        cdef unsigned int i = 1
        while i < self.MAX_VAL:
            if i & self._val:
                size += 1

            i <<= 1

        return size

    def add(self, flag):
        self._val |= flag

    def discard(self, flag):
        # NB(directxman12): the 0xFFFFFFFF mask is needed to
        #                   make Python's invert work properly
        self._val = self._val & (~flag & 0xFFFFFFFF)

    def __and__(self, other):
        if isinstance(other, numbers.Integral):
            return self._val & other
        else:
            return super(GenericFlagSet, self).__and__(other)

    def __rand__(self, other):
        return self.__and__(other)

    def __or__(self, other):
        if isinstance(other, numbers.Integral):
            return self._val | other
        else:
            return super(GenericFlagSet, self).__or__(other)

    def __ror__(self, other):
        return self.__or__(other)

    def __xor__(self, other):
        if isinstance(other, numbers.Integral):
            return self._val ^ other
        else:
            return super(GenericFlagSet, self).__xor__(other)

    def __rxor__(self, other):
        return self.__xor__(other)

    def __int__(self):
        return self._val

    def __long__(self):
        return long(self._val)

    def __eq__(self, other):
        if isinstance(other, GenericFlagSet):
            return self._val == other._val
        else:
            return False

    def __ne__(self, other):
        return not self.__eq__(other)

    def __repr__(self):
        bits = "{0:032b}".format(self._val & 0xFFFFFFFF)
        return "<{name} {bits}>".format(name=type(self).__name__,
                                        bits=bits)


class IntEnumFlagSet(GenericFlagSet):

    __slots__ = ('_val', '_enum')

    def __init__(self, enum, flags=None):
        if not issubclass(enum, IntEnum):
            raise Exception('"enum" not an Enum')
        self._enum = enum
        super(IntEnumFlagSet, self).__init__(flags)

    def __iter__(self):
        for i in super(IntEnumFlagSet, self).__iter__():
            yield self._enum(i)

    def __repr__(self):
        fmt_str = "{name}({enum}, [{vals}])"
        vals = ', '.join([elem.name for elem in self])
        return fmt_str.format(name=type(self).__name__,
                              enum=self._enum.__name__,
                              vals=vals)

    def __and__(self, other):
        if isinstance(other, self._enum):
            return other in self
        else:
            res = super(IntEnumFlagSet, self).__and__(other)
            if isinstance(res, GenericFlagSet):
                return IntEnumFlagSet(self._enum, res)
            else:
                return res

    def __or__(self, other):
        if isinstance(other, self._enum):
            cpy = copy.copy(self)
            cpy.add(other)
            return cpy
        else:
            res = super(IntEnumFlagSet, self).__or__(other)
            if isinstance(res, GenericFlagSet):
                return IntEnumFlagSet(self._enum, res)
            else:
                return res

    def __xor__(self, other):
        if isinstance(other, self._enum):
            cpy = copy.copy(self)
            cpy._val = cpy._val ^ other
            return cpy
        else:
            res = super(IntEnumFlagSet, self).__xor__(other)
            if isinstance(res, GenericFlagSet):
                return IntEnumFlagSet(self._enum, res)
            else:
                return res

    def __sub__(self, other):
        return IntEnumFlagSet(self._enum,
                              super(IntEnumFlagSet, self).__sub__(other))

    @classmethod
    def _from_iterable(cls, it):
        return GenericFlagSet(it)
