FC = FC or utils.which 'gfortran' or utils.which 'g95'
if not FC then
    quit("cannot find either gfortran or g95 on your path")
end
f = lake.new_lang(c,{ext='.f90'})
f.uses_dfile = false
f.auto_deps = false
lake.register(f,'.f90 .for .f')
f.compile = '$(FC) -c $(CFLAGS)  $(INPUT)'
f.link = '$(FC) $(DEPENDS) $(LIBS) -o $(TARGET)'
lake.add_prog(f)
