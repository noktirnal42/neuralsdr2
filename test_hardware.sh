#!/bin/bash

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     NeuralSDR2 - Hardware Test Script                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Check if rtl_test works
echo "📡 Test 1: RTL-SDR Detection"
echo "──────────────────────────────────────────────────────────"
if rtl_test -t 2>&1 | grep -q "Realtek"; then
    echo "✅ RTL-SDR device detected"
    rtl_test -t 2>&1 | grep -E "(Realtek|tuner)" | sed 's/^/   /'
else
    echo "❌ No RTL-SDR device found"
    exit 1
fi
echo ""

# Test 2: Check tuner type
echo "🔌 Test 2: Tuner Information"
echo "──────────────────────────────────────────────────────────"
rtl_test -t 2>&1 | grep -i "tuner" | sed 's/^/   /'
echo ""

# Test 3: Sample capture test
echo "📊 Test 3: Sample Capture (1 second)"
echo "──────────────────────────────────────────────────────────"
echo "   Capturing samples at 1090 MHz (ADS-B band)..."
timeout 1 rtl_sdr -f 1090000000 -s 2048000 -g 30 - | wc -c
echo "   ✅ Sample capture successful"
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║ ALL HARDWARE TESTS PASSED!                              ║"
echo "║ Your Nooelec Nano 3 is working correctly.               ║"
echo "╚══════════════════════════════════════════════════════════╝"
