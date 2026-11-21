# vault/

Encrypted secrets go here, for example `secrets.yml`, created with:

```bash
ansible-vault create vault/secrets.yml
```

Only encrypted files may be committed. The vault password itself is never stored in Git.
