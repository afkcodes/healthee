"""Tests for the Zepp importer. Standard library only, like the tool.

    python3 -m unittest discover -s scripts/zepp_import/tests -t scripts

Nothing here touches the network: Zepp and Healthee are in-process fakes behind the
`transport.Send` seam (`fake_zepp.py`, `fake_healthee.py`), and the one test that opens a
socket (`test_transport.py`) talks to a server it starts on loopback.
"""
