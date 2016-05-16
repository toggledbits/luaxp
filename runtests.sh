#! /bin/sh

lua test/t1.lua | grep 'FAIL'
lua test/t2.lua | grep 'FAIL'
lua test/t3.lua | grep 'FAIL'
lua test/t4.lua | grep 'FAIL'
lua test/t5.lua | grep 'FAIL'
lua test/t6.lua | grep 'FAIL'
lua test/t7.lua | grep 'FAIL'
