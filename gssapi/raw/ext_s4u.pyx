GSSAPI="BASE"  # This ensures that a full module is generated by Cython

from gssapi.raw.cython_types cimport *
from gssapi.raw.cython_converters cimport c_create_oid_set
from gssapi.raw.cython_converters cimport c_get_mech_oid_set
from gssapi.raw.cython_converters cimport c_py_ttl_to_c, c_c_ttl_to_py
from gssapi.raw.creds cimport Creds
from gssapi.raw.names cimport Name
from gssapi.raw.oids cimport OID

from gssapi.raw.misc import GSSError
from gssapi.raw.named_tuples import AcquireCredResult, AddCredResult


cdef extern from "python_gssapi_ext.h":
    OM_uint32 gss_acquire_cred_impersonate_name(OM_uint32 *min_stat,
                                                const gss_cred_id_t imp_creds,
                                                const gss_name_t name,
                                                OM_uint32 ttl,
                                                const gss_OID_set mechs,
                                                gss_cred_usage_t cred_usage,
                                                gss_cred_id_t *output_creds,
                                                gss_OID_set *actual_mechs,
                                                OM_uint32 *actual_ttl) nogil

    OM_uint32 gss_add_cred_impersonate_name(OM_uint32 *min_stat,
                                            gss_cred_id_t base_creds,
                                            const gss_cred_id_t imp_creds,
                                            const gss_name_t name,
                                            const gss_OID mech,
                                            gss_cred_usage_t cred_usage,
                                            OM_uint32 initiator_ttl,
                                            OM_uint32 acceptor_ttl,
                                            gss_cred_id_t *output_creds,
                                            gss_OID_set *actual_mechs,
                                            OM_uint32 *actual_init_ttl,
                                            OM_uint32 *actual_accept_ttl) nogil


def acquire_cred_impersonate_name(Creds impersonator_cred not None,
                                  Name name not None, lifetime=None,
                                  mechs=None, usage='initiate'):
    cdef gss_OID_set desired_mechs
    if mechs is not None:
        desired_mechs = c_get_mech_oid_set(mechs)
    else:
        desired_mechs = GSS_C_NO_OID_SET

    cdef OM_uint32 input_ttl = c_py_ttl_to_c(lifetime)
    cdef gss_name_t c_name = name.raw_name

    cdef gss_cred_usage_t c_usage
    if usage == 'initiate':
        c_usage = GSS_C_INITIATE
    elif usage == 'accept':
        c_usage = GSS_C_ACCEPT
    elif usage == 'both':
        c_usage = GSS_C_BOTH
    else:
        raise ValueError(f'Invalid usage "{usage}" - permitted values are '
                         '"initiate", "accept", and "both"')

    cdef gss_cred_id_t creds
    cdef gss_OID_set actual_mechs
    cdef OM_uint32 actual_ttl

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_acquire_cred_impersonate_name(
            &min_stat, impersonator_cred.raw_creds, name.raw_name,
            input_ttl, desired_mechs, c_usage, &creds, &actual_mechs,
            &actual_ttl)

    cdef OM_uint32 tmp_min_stat
    if mechs is not None:
        gss_release_oid_set(&tmp_min_stat, &desired_mechs)

    cdef Creds rc = Creds()
    if maj_stat == GSS_S_COMPLETE:
        rc.raw_creds = creds
        return AcquireCredResult(rc, c_create_oid_set(actual_mechs),
                                 c_c_ttl_to_py(actual_ttl))
    else:
        raise GSSError(maj_stat, min_stat)


def add_cred_impersonate_name(Creds input_cred,
                              Creds impersonator_cred not None,
                              Name name not None, OID mech not None,
                              usage='initiate', init_lifetime=None,
                              accept_lifetime=None):
    cdef OM_uint32 input_initiator_ttl = c_py_ttl_to_c(init_lifetime)
    cdef OM_uint32 input_acceptor_ttl = c_py_ttl_to_c(accept_lifetime)
    cdef gss_name_t c_name = name.raw_name

    cdef gss_cred_usage_t c_usage
    if usage == 'initiate':
        c_usage = GSS_C_INITIATE
    elif usage == 'accept':
        c_usage = GSS_C_ACCEPT
    elif usage == 'both':
        c_usage = GSS_C_BOTH
    else:
        raise ValueError(f'Invalid usage "{usage}" - permitted values are '
                         '"initiate", "accept", and "both"')

    cdef gss_cred_id_t raw_input_cred
    if input_cred is not None:
        raw_input_cred = input_cred.raw_creds
    else:
        raw_input_cred = GSS_C_NO_CREDENTIAL

    cdef gss_cred_id_t creds
    cdef gss_OID_set actual_mechs
    cdef OM_uint32 actual_initiator_ttl
    cdef OM_uint32 actual_acceptor_ttl

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_add_cred_impersonate_name(&min_stat, raw_input_cred,
                                                 impersonator_cred.raw_creds,
                                                 name.raw_name, &mech.raw_oid,
                                                 c_usage, input_initiator_ttl,
                                                 input_acceptor_ttl, &creds,
                                                 &actual_mechs,
                                                 &actual_initiator_ttl,
                                                 &actual_acceptor_ttl)

    cdef Creds rc
    if maj_stat == GSS_S_COMPLETE:
        rc = Creds()
        rc.raw_creds = creds
        return AddCredResult(rc, c_create_oid_set(actual_mechs),
                             c_c_ttl_to_py(actual_initiator_ttl),
                             c_c_ttl_to_py(actual_acceptor_ttl))
    else:
        raise GSSError(maj_stat, min_stat)
