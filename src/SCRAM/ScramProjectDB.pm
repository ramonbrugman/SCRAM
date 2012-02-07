package SCRAM::ScramProjectDB;
use Utilities::Verbose;
use Utilities::AddDir;
use File::Basename;
require 5.004;
@ISA=qw(Utilities::Verbose);

sub new()
{
  my $class=shift;
  my $self={};
  bless $self, $class;
  $self->{scramrc}='etc/scramrc';
  $self->{linkfile}='links.db';
  $self->{archs}{$ENV{SCRAM_ARCH}}=1;
  $self->{listcache}= {};
  $ENV{SCRAM_LOOKUPDB}=&Utilities::AddDir::fixpath($ENV{SCRAM_LOOKUPDB});
  $self->_initDB();
  return $self;
}

sub getarea ()
{
  my $self=shift;
  my $name=shift;
  my $version=shift;
  my $arch = shift || $ENV{SCRAM_ARCH};
  my $data = $self->_findProjects($name,$version,1,$arch);
  if (scalar(@$data) == 1){ return $self->_getAreaObject($data->[0],$arch); }
  my $list = $self->updatearchs($name,$version);
  delete $list->{$arch};
  my @archs = keys %{$list};
  if (scalar(@archs)==1){return $self->_getAreaObject($list->{$archs[0]}[0], $archs[0]);}
  return undef;
}

sub listlinks()
{
  my $self=shift;
  my $links={};
  $links->{local}=[]; $links->{linked}=[]; 
  my %local=();
  foreach my $d (@{$self->{LocalLinks}}){$local{$d}=1; push @{$links->{local}},$d;}
  my $cnt=scalar(@{$self->{DBS}{order}});
  for(my $i=1;$i<$cnt;$i++)
  {
    my $d=$self->{DBS}{order}[$i];
    if (!exists $local{$d}){push @{$links->{linked}},$d;}
  }
  return $links;
}

sub listall()
{
  return _findProjects(@_);
}

sub updatearchs()
{
  my ($self,$name,$version)=@_;
  $self->{listcache} = {};
  foreach my $arch (keys %{$self->{archs}})
  {
    my $data = $self->_findProjects($name,$version,1,$arch);
    if (scalar(@$data)==1){$self->{listcache}{$arch}=$data;}
  }
  return $self->{listcache};
}

sub link()
{
  my ($self,$db)=@_;
  $db=~s/^\s*file://o; $db=~s/\s//go;
  if ($db eq ""){return 1;}
  $db=&Utilities::AddDir::fixpath($db);
  if ($db eq $ENV{SCRAM_LOOKUPDB}){return 1;}
  if (-d $db)
  {
    foreach my $d (@{$self->{LocalLinks}}){if ($db eq $d){return 0;}}
    push @{$self->{LocalLinks}},$db;
    $self->_save ();
    return 0;
  }
  return 1;
}

sub unlink()
{
  my ($self,$db)=@_;
  $db=~s/^\s*file://o; $db=~s/\s//go;
  if ($db eq ""){return 1;}
  $db=&Utilities::AddDir::fixpath($db);
  my $cnt=scalar(@{$self->{LocalLinks}});
  for(my $i=0;$i<$cnt;$i++)
  {
    if ($db eq $self->{LocalLinks}[$i])
    {
      for(my $j=$i+1;$j<$cnt;$j++){$self->{LocalLinks}[$j-1]=$self->{LocalLinks}[$j];}
      pop @{$self->{LocalLinks}};
      $self->_save ();
      return 0;
    }
  }
  return 1;
}

##################################################

sub _getAreaObject ()
{
  my ($self,$data,$arch)=@_;
  my $area=Configuration::ConfigArea->new($arch);
  my $loc = $data->[2];
  if ($area->bootstrapfromlocation($loc) == 1)
  {
    $area = undef;
    print STDERR "ERROR: Attempt to ressurect ",$data->[0]," ",$data->[1]," from $loc unsuccessful\n";
    print STDERR "ERROR: $loc does not look like a valid release area for SCRAM_ARCH $arch.\n";
  }
  return $area;
}

sub _save ()
{
  my $self=shift;
  my $filename = $ENV{SCRAM_LOOKUPDB_WRITE}."/".$self->{scramrc};
  &Utilities::AddDir::adddir($filename);
  $filename.="/".$self->{linkfile};
  my $fh;
  if (!open ( $fh, ">$filename" )){die "Can not open file for writing: $filename\n";}
  foreach my $db (@{$self->{LocalLinks}}){if ($db ne ""){print $fh "$db\n";}}
  close($fh);
  my $mode=0644;
  chmod $mode,$filename;
}

sub _initDB ()
{
  my $self=shift;
  my $scramdb=shift;
  my $cache=shift || {};
  my $local=0;
  my $localdb=$ENV{SCRAM_LOOKUPDB};
  if (!defined $scramdb)
  {
    $scramdb=$localdb;
    $self->{DBS}{order}=[];
    $self->{DBS}{uniq}={};
    $self->{LocalLinks}=[];
    $local=1;
  }
  if (exists $self->{DBS}{uniq}{$scramdb}){return;}
  $self->{DBS}{uniq}{$scramdb}={};
  push @{$self->{DBS}{order}},$scramdb;
  my $db="${scramdb}/".$self->{scramrc};
  my $ref;
  foreach my $f (glob("${db}/*.map"))
  {
    if((-f $f) && (open($ref,$f)))
    {
      while(my $line=<$ref>)
      {
        chomp $line; $line=~s/\s//go;
        if ($line=~/^([^=]+)=(.+)$/o){$self->{DBS}{uniq}{$scramdb}{uc($1)}{$2}=1;}
      }
      close($ref);
    }
  }
  foreach my $f (glob("${db}/*.arch"))
  {
    if ($f=~/^${db}\/(.*)\.arch$/){$self->{archs}{$1}=1;}
  }
  if (!$local)
  {
    foreach my $proj (keys %{$self->{DBS}{uniq}{$localdb}})
    {
      if (!exists $self->{DBS}{uniq}{$scramdb}{$proj})
      {
        foreach my $path (keys %{$self->{DBS}{uniq}{$localdb}{$proj}}){$self->{DBS}{uniq}{$scramdb}{$proj}{$path}=1;}
      }
    }
  }
  if(open($ref, "${db}/".$self->{linkfile}))
  {
    my %uniq=();
    while(my $line=<$ref>)
    {
      chomp $line; $line=~s/\s//go;
      if (($line eq "") || (!-d $line)){next;}
      $line=&Utilities::AddDir::fixpath($line);
      if (exists $uniq{$line}){next;}
      $uniq{$line}=1;
      $self->_initDB($line,$cache);
      if ($local){push @{$self->{LocalLinks}},$line;}
    }
    close($ref);
  }
}

sub _findProjects()
{
  my $self=shift;
  my $proj=shift || '.+';
  my $ver=shift || '.+';
  my $exact=shift  || undef;
  my $arch=shift || $ENV{SCRAM_ARCH};
  my %data=();
  my %uniq=();
  foreach my $base (@{$self->{DBS}{order}})
  {
    foreach my $p (keys %{$self->{DBS}{uniq}{$base}})
    {
      if ($p!~/^$proj$/){next;}
      my $db="${base}/".join(" ${base}/",keys %{$self->{DBS}{uniq}{$base}{$p}});
      $db=~s/\$(\{|\(|)SCRAM_ARCH(\}|\)|)/$arch/g;
      foreach my $fd (glob($db))
      {
        if (!-d $fd){next;}
	my $d=basename($fd);
	if ($d=~/^$ver$/)
	{
	  if ($exact){return [[$p,$d,$fd]];}
	  elsif(!exists $uniq{"$p:$d"})
	  {
	    $uniq{"$p:$d"}=1;
	    my $m = (stat($fd))[9];
	    $data{$m}{$p}{$d}=$fd;
	  }
	}
      }
    }
  }
  my $xdata = [];
  foreach my $m (sort {$a <=> $b} keys %data)
  {
    foreach my $p (keys %{$data{$m}})
    {
      foreach my $v (keys %{$data{$m}{$p}})
      {
        push @$xdata, [$p,$v,$data{$m}{$p}{$v}];
      }
    }
  }
  return $xdata;
}
