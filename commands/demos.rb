
command_set :demos do
  command 'wait' do
    admin_only
    sleep argstr.to_i
    respond "waited #{argstr}"
  end
  
  command 'crash' do
    admin_only
    respond "OHSHI\u2014"
    raise
  end
  
  command 'wait-crash' do
    admin_only
    sleep argstr.to_i
    respond "OHSHI\u2014"
    raise
  end
  
  command 'flood' do
    admin_only
    35.times do |n|
      respond "#{n+1} #{argstr}"
    end
  end
end

