function certs_extract_dod --description='This process is a pain. Get the p7b, convert it to a PEM, split the pem, rename the individual files.'
    set src_file $argv[1]
    openssl pkcs7 -inform der -in $src_file -print_certs -out $src_file.pem
    mkdir certs
    cat $src_file.pem | awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} {print > "cert" n ".pem"}'
    mv cert*.pem certs
    pushd certs
    for n in (ls cert*.pem)
        set new_name (openssl x509 -noout -subject -in $n | cut -d '=' -f 7 | xargs | string replace -a ' ' '_')
        mv $n $new_name.pem
    end
    popd
end
