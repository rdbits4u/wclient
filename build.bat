
rem building

cd ..\rdpc
zig build -Doptimize=ReleaseFast -Dstrip=true --summary all

cd ..\svc
zig build -Doptimize=ReleaseFast -Dstrip=true --summary all

cd ..\cliprdr
zig build -Doptimize=ReleaseFast -Dstrip=true --summary all

cd ..\rdpsnd
zig build -Doptimize=ReleaseFast -Dstrip=true --summary all

cd ..\wclient
zig build -Doptimize=ReleaseFast -Dstrip=true --summary all

copy ..\rdpc\zig-out\bin\rdpc.dll       zig-out\bin
copy ..\svc\zig-out\bin\svc.dll         zig-out\bin
copy ..\cliprdr\zig-out\bin\cliprdr.dll zig-out\bin
copy ..\rdpsnd\zig-out\bin\rdpsnd.dll   zig-out\bin
