#!/usr/bin/env python

import os
import sys
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.x509.oid import ExtensionOID
from datetime import datetime

salt_master_ca_path = '/etc/pki/ca/salt_master_ca/certs/'
certs = []
elem_in_list = False

_files = os.listdir(salt_master_ca_path)
for _file in _files:
  _file_obj      = open(salt_master_ca_path + _file, 'r')
  pem_data       = _file_obj.read()
  _file_obj.close()

  cert_serial    = _file.split('.')[0].lower()
  cert           = x509.load_pem_x509_certificate(pem_data, default_backend())
  cert_date      = datetime.strptime(str(cert.not_valid_before), '%Y-%m-%d %H:%M:%S').strftime('%s')
  cert_exts      = cert.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
  cert_exts_list = cert_exts.value.get_values_for_type(x509.DNSName)

  for _name in cert.subject:
    if _name.oid.dotted_string == '2.5.4.3':
      cert_cn = _name.value

  for elem in certs:
    if (elem[0] == cert_cn) and (elem[1] == cert_exts_list):
      elem_in_list = True
      if elem[2] < cert_date:
        elem[2] = cert_date

  if not elem_in_list:
    certs.append([ cert_cn, cert_exts_list, cert_date, cert_serial ])

  elem_in_list = False

for elem in certs:
  print salt_master_ca_path + elem[3].upper() + '.crt (' + str(elem[0]) + ', ' + ', '.join(map(str, elem[1])) + ')'
