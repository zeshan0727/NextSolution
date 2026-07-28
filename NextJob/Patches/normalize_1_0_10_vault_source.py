from pathlib import Path

path = Path("NextJob/Vault/VaultStore.swift")
source = path.read_text(encoding="utf-8")
malformed = r'CharacterSet(charactersIn: "/:\?%*|"<>")'
correct = r'CharacterSet(charactersIn: "/:\\?%*|\"<>")'

if malformed in source:
    source = source.replace(malformed, correct)
elif correct not in source:
    raise RuntimeError("Could not locate the Secure Logins filename character set")

path.write_text(source, encoding="utf-8")
print("Normalised Secure Logins attachment filename escaping.")
