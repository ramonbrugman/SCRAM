#____________________________________________________________________ 
# File: SCRAM.pm
#____________________________________________________________________ 
#  
# Author: Shaun Ashby <Shaun.Ashby@cern.ch>
# Update: 2003-06-18 18:04:35+0200
# Revision: $Id: SCRAM.pm,v 1.1.2.17 2004/11/23 10:32:40 sashby Exp $ 
#
# Copyright: 2003 (C) Shaun Ashby
#
#--------------------------------------------------------------------
package SCRAM::SCRAM;
require 5.004;

use Exporter;
use SCRAM::Helper;
use Utilities::Architecture;
use Utilities::Verbose;
use SCRAM::CMD;

@ISA=qw(Exporter Utilities::Verbose SCRAM::CMD);
@EXPORT_OK=qw( );

sub new()
   {
   ###############################################################
   # new()                                                       #
   ###############################################################
   # modified : Wed Jun 18 18:04:48 2003 / SFA                   #
   # params   :                                                  #
   #          :                                                  #
   # function :                                                  #
   #          :                                                  #
   ###############################################################
   my $proto=shift;
   my $class=ref($proto) || $proto;
   my $self=
      {
      SCRAM_PREREQCHECK => undef,
      SCRAM_VERSIONCHECK => undef,
      SCRAM_ALLOWEDCMDS => undef,
      SCRAM_ARCH => undef || $ENV{SCRAM_ARCH},
      SCRAM_VERBOSE => 0 || $ENV{SCRAM_VERBOSE},
      SCRAM_BUILDVERBOSE => 0 || $ENV{SCRAM_BUILDVERBOSE},
      SCRAM_DEBUG => 0 || $ENV{SCRAM_DEBUG},
      SCRAM_VERSION => undef,
      SCRAM_CVSID => '$Id: SCRAM.pm,v 1.1.2.17 2004/11/23 10:32:40 sashby Exp $',
      SCRAM_TOOLMANAGER => undef,
      SCRAM_HELPER => new Helper,
      ISPROJECT => undef,
      };
  
   bless $self,$class;

   $self->_init();
   return $self;
   }

sub _init()
   {
   my $self=shift;

   # Store available ommands:
   $self->commands();
   # Set up the environment:
   $self->_initlocalarea();
   $self->_initreleasearea();
   $self->_initenv();
   # Check that we have everything to
   # be able to run:
   $self->prerequisites();
   # Create new interface object:
   $self->scramfunctions();
   # See which version of SCRAM
   # should be used:
   $self->versioncheck();
   return $self;
   }

sub commands()
   {
   my $self = shift;
   my @env_commands = qw(version arch runtime);
   my @info_commands = qw(list db urlget); 
   my @buildenv_commands = qw(project setup tool);
   my @build_commands=qw(build install remove);
   my @dev_cmds=qw();

   return ($self->{SCRAM_ALLOWEDCMDS} =
	   [@env_commands,@info_commands,@buildenv_commands,@build_commands,@dev_cmds]);
   }

sub showcommands()
   {
   my $self=shift;
   return @{$self->{SCRAM_ALLOWEDCMDS}};
   }

sub execcommand()
   {
   my $self = shift;
   my ($cmd,@ARGS) = @_;
   my $rval=0;
   my $status=1;
   
   local @ARGV = @ARGS;

   map
      {
      if ( $_ =~ /^$cmd/i)
	 {
	 $status=0; # Command found so OK;
	 $rval = $self->$_(@ARGV);
	 }
      } $self->showcommands();

   # Print usage and exit if no command matched:
   if ($status)
      {
      print $self->usage();
      $rval = 1;
      }

   return $rval;
   }

sub prerequisites()
   {
   my $self=shift;
   $self->{SCRAM_PREREQCHECK} = 1;
   return $self;
   }

sub versioncheck()
   {
   my $self=shift;
   my $version;

   # This routine checks for consistency in SCRAM versions. Only
   # applies in a project area since outside we'll be using the
   # current release anyway. If we're in a project we use the "scram_version"
   # file in config directory:
   if ($self->islocal())
      {
      my $versionfile=$ENV{LOCALTOP}."/".$ENV{SCRAM_CONFIGDIR}."/scram_version";
      if ( -f $versionfile )
	 {
	 open (VERSION, "<".$versionfile);
	 $version=<VERSION>;
	 chomp $version;
	 }
      # Spawn the required version:
      $self->scramfunctions()->spawnversion($version,@ARGV), if (defined ($version));
      }

   $self->{SCRAM_VERSIONCHECK} = 1;
   $self->{SCRAM_VERSION} = $version;
   return $self;
   }

sub _initenv()
   {
   my $self=shift;

   # Read the Environment file if inside a project:
   $self->localarea()->copyenv(\%ENV), if ($self->islocal());

   # Check and set architectuer:
   if (! defined $self->{SCRAM_ARCH})
      {
      my $a = Architecture->new();
      $self->architecture($a->arch());
      $ENV{SCRAM_ARCH} = $self->architecture();
      }
   
   # Set up some environment variables:
   $ENV{SCRAM_TMP}="tmp";
   $ENV{SCRAM_INTwork}=$ENV{SCRAM_TMP}."/".$ENV{SCRAM_ARCH};
   $ENV{SCRAM_SOURCEDIR}="src";
   $ENV{SCRAM_INTlog}="logs";
   ($ENV{SCRAM_BASEDIR}=$ENV{SCRAM_HOME}) =~ s/(.*)\/.*/$1/;
   $ENV{SCRAM_BASEDIR} =~ s!:$!:/! if $^O eq 'MSWin32';
   $ENV{SCRAM_TOOL_HOME}=$ENV{SCRAM_HOME}."/src";
   
   # Need a lookup database:
   if ( ! ( exists $ENV{SCRAM_LOOKUPDB} ) )
      {
      if ( -d "$ENV{SCRAM_BASEDIR}/scramdb/" )
	 {
	 $ENV{SCRAM_LOOKUPDB}="$ENV{SCRAM_BASEDIR}/scramdb/project.lookup";
	 }
      else
	 {
	 # Just store in user home directory:
	 $ENV{SCRAM_LOOKUPDB}=$ENV{HOME}."/project.lookup";
	 }
      }
   }

sub _loadscramdb()
   {
   my $self=shift;
   # Read the scram database to keep track of which
   # projects are scram-managed:
   my @scramprojects = $self->getprojectsfromDB();
   $self->{SCRAM_PDB}={};
   
   foreach my $project (@scramprojects)
      {
      my $parea=$self->scramfunctions()->scramprojectdb()->getarea($project->[0], $project->[1]);
      if (defined ($parea) && $parea->location() ne '')
	 {
	 # Store the name of the project as lowercase to make lookups easier
	 # during setup. When storing the individual project name/version entries, mangle the
	 # version with the real name, separated by a :  for access to this data needed
	 # when getting the area:
	 $self->{SCRAM_PDB}->{lc($project->[0])}->{$project->[0].":".$project->[1]} = $parea->location(); 
	 }
      }
   
   return $self->{SCRAM_PDB};
   }

sub islocal()
   {
   my $self=shift;
   
   @_ ? $self->{ISPROJECT} = shift # Modify or
      : $self->{ISPROJECT};        # retrieve

   }

sub scramfunctions()
   {
   my $self=shift;
   
   if ( ! defined $self->{functions} )
      {
      require Scram::ScramFunctions;
      $self->{functions} = Scram::ScramFunctions->new();
      $self->architecture($ENV{SCRAM_ARCH});
      }
   else
      {
      return $self->{functions};
      }
   }

sub _initlocalarea()
   {
   my $self=shift;
   
   if ( ! defined ($self->localarea()) )
      {
      require Configuration::ConfigArea;
      $self->localarea(Configuration::ConfigArea->new());

      # Set LOCALTOP if we're inside project area:
      $ENV{LOCALTOP} = $self->localarea()->location();
      
      if ( ! defined ($ENV{LOCALTOP}) )
	 {
	 if ( $self->localarea()->bootstrapfromlocation() )
	    {
	    # We're not in a local area: 
	    $self->localarea(undef);
	    }
	 else
	    {
	    $self->localarea()->archname($self->scramfunctions()->arch());
	    }
	 }
      else
	 {
	 $self->localarea()->bootstrapfromlocation($ENV{LOCALTOP});
	 }
      
      # Now create some environment variables that need LOCALTOP:
      if (defined ($ENV{LOCALTOP}))
	 {
	 ($ENV{THISDIR}=cwd) =~ s/^\Q$ENV{LOCALTOP}\L//;
	 $ENV{THISDIR} =~ s/^\///;
	 # Also set LOCALRT:
	 $ENV{LOCALRT} = $ENV{LOCALTOP};
	 $self->islocal(1);
	 }
      elsif (defined ($ENV{'LOCALRT'}))
	 {
	 $ENV{LOCALTOP} = $ENV{'LOCALRT'};
	 ($ENV{THISDIR}=cwd) =~ s/^\Q$ENV{LOCALTOP}\L//;
	 $ENV{THISDIR} =~ s/^\///;
	 $self->islocal(1);
	 }
      else
	 {
	 # We're not in a project area. Some commands will not need to
	 # be in an area to work so we just set a flag:
	 $self->islocal(0);
	 }
      }
   }

sub align
   {
   my $self=shift;   
   $self->localarea()->align(); 
   }

sub localarea()
   {
   my $self=shift;

   @_ ? $self->{localarea} = shift # Modify or
      : $self->{localarea};        # retrieve
   }

sub _initreleasearea()
   {
   my $self=shift;

   if ( ! defined $self->releasearea() )
      {
      require Configuration::ConfigArea;
      $self->releasearea(Configuration::ConfigArea->new());
      $self->releasearea()->bootstrapfromlocation($ENV{RELEASETOP});
      }

   return $self->releasearea();
   }

sub releasearea()
   {
   my $self=shift;
   
   @_ ? $self->{releasearea} = shift # Modify or
      : $self->{releasearea};        # retrieve
   }

sub debuglevel()
   {
   my $self=shift;

   @_ ? $self->{SCRAM_DEBUG} = shift # Modify or
      : $self->{SCRAM_DEBUG};        # retrieve
   }

sub cvsid()
   {
   my $self=shift;

   @_ ? $self->{SCRAM_CVSID} = shift # Modify or
      : $self->{SCRAM_CVSID};        # retrieve
   }

sub architecture()
   {
   my $self=shift;

   @_ ? $self->{SCRAM_ARCH} = shift # Modify or
      : $self->{SCRAM_ARCH};        # retrieve
   }

sub getprojectsfromDB()
   {
   my $self=shift;

   # Get list of projects from scram database and return them:
   return ($self->scramfunctions()->scramprojectdb()->listall());
   }

sub toolmanager
   {
   my $self = shift;
   my ($location)=@_;
   $location||=$self->localarea();
   
   # This subroutine is used to reload the ToolManager object from file.
   # If this file does not exist, it implies that the area has not yet been set
   # up so we make a copy of whichever one exists and tell the user to run "scram setup":
   if ( -r $location->toolcachename() )
      {
      # Cache exists, so read it:
      $self->info("Reading tool data from ToolCache.db.") if ($self->{SCRAM_DEBUG});
      use Cache::CacheUtilities;
      $toolmanager=&Cache::CacheUtilities::read($location->toolcachename());
      # If this area has been cloned, we must make some adjustments so that the cache
      # is really local and refers to all settings of local area (admin dir etc.):
      if ($ENV{RELEASETOP} && ! $toolmanager->cloned_tm())
	 {
	 $self->info("Cloning release-area ToolCache.db. Localising settings...") if ($self->{SCRAM_DEBUG});
	 $toolmanager->clone($location);
	 $toolmanager->writecache(); # Save the new cache
	 }
      }
   else
      {
      my $found;
      local $toolcachedir;

      # Path to cache dir in SCRAM area:
      my $cachedir = $ENV{LOCALTOP}."/.SCRAM";
      # Get a list of subdirs in this dir. There will be a subdir for
      # each known architecture:
      opendir(CACHEDIR, $cachedir) || die "SCRAM: $cachedir: cannot read: $!\n";
      # Skip . and .. but include other dirs:
      my @ARCHDIRS = map { "$cachedir/$_" } grep ($_ ne "." && $_ ne "..", readdir(CACHEDIR));
      
      # If we don't have our arch subdir, create it before copying:
      if (! -d $cachedir."/".$ENV{SCRAM_ARCH})
	 {
	 mkdir($cachedir."/".$ENV{SCRAM_ARCH}) || die
	    "SCRAM: Unable to create directory $cachedir: $!","\n";
	 }
      
      # Run over the dirs and check for a cache:
      foreach $toolcachedir (@ARCHDIRS)
	 {
	 # If there's a cache file, copy it:
	 if ( -f $toolcachedir."/ToolCache.db" )
	    {
	    # If we found one, read it:
	    $found=$toolcachedir."/ToolCache.db";
	    use Cache::CacheUtilities;
	    # Read, make arch-specific changes then write out:
	    $toolmanager=&Cache::CacheUtilities::read($found);
	    $toolmanager->arch_change_after_copy($ENV{SCRAM_ARCH}, $location->toolcachename());
	    last;
	    }
	 else
	    {
	    next;
	    }	 
	 }
      
      if (!$found)
	 {
	 $self->scramerror("Unable to read a tool cache. Maybe the area is not yet set up?");
	 }
      }
   
   return $toolmanager;
   }

sub checklocal()
   {
   my $self=shift;
   $self->scramfatal("Unable to locate the top of local release. Exitting."), if (! $self->islocal());   
   }

#### Verbosity routines (warnings and error messages) ####
sub msg()
   {
   my $self=shift;
   return "> ",join(' ',@_);
   }

sub warning()
   {
   my $self=shift;
   return "warning: ",join(' ',@_);
   }

sub error()
   {
   my $self=shift;
   return "error: ",join(' ',@_);
   }

sub fatal()
   {
   my $self=shift;
   return "fatal: ",join(' ',@_);
   }

sub info()
   {
   my $self=shift;
   print STDOUT "SCRAM info: ",$self->msg(@_),"\n";   
   }

sub scramwarning()
   {
   my $self=shift;
   # Send errors to STDERR when piping:
   if ( -t STDERR )
      {
      print STDERR "SCRAM ",$self->warning(@_),"\n";   
      }
   else
      {
      print "SCRAM ",$self->warning(@_),"\n";
      }
   }
   
sub scramerror()
   {
   my $self=shift;
   
   # Send errors to STDERR when piping:
   if ( -t STDERR )
      {
      print STDERR "SCRAM ",$self->error(@_),"\n";   
      }
   else
      {
      print "SCRAM ",$self->error(@_),"\n";  
      }
   exit(1);
   }

sub scramfatal()
   {
   my $self=shift;
   print "SCRAM ",$self->fatal(@_),"\n";
   exit(1);
   }

sub classverbosity
   {
   my $self=shift;
   my $classlist=shift;
   
   # $classlist might be a string of classes so we should split and store
   # each element, then set classverbose for each class individually:
   my @classes = split(" ",$classlist);
   
   foreach my $class (@classes)
      {
      print "Verbose mode for ",$class," switched ".$::bold."ON".$::normal."\n" ;
      # Set the verbosity via scram functions:
      $self->scramfunctions()->classverbose($class,1);
      }
   }

sub fullverbosity
   {
   my $self=shift;
   
   require "PackageList.pm";
   foreach my $class (@PackageList)
      {
      $self->classverbosity($class);
      }
   }


#### Usage block ####
sub usage()
   {
   my $self=shift;
   my $usage;
   
   $usage.="*************************************************************************\n";
   $usage.="SCRAM HELP ------------- Recognised Commands\n";
   $usage.="*************************************************************************\n";
   $usage.="\n";

   map { $usage.="\t$::bold scram ".$_."$::normal\n"  } $self->showcommands();
   
   $usage.="\n";
   $usage.= "Help on individual commands is available through";
   $usage.="\n\n";
   $usage.= "\tscram <command> -help";
   $usage.="\n\n";
   $usage.="\nOptions:\n";
   $usage.="--------\n";
   $usage.=sprintf("%-28s : %-55s\n","-help","Show this help page.");
   $usage.=sprintf("%-28s : %-55s\n","-verbose <class> ",
		   "Activate the verbose function on the specified class or list of classes.");
   $usage.=sprintf("%-28s : %-55s\n","-debug ","Activate the verbose function on all SCRAM classes.");
   $usage.="\n";
   $usage.=sprintf("%-28s : %-55s\n","-arch <architecture>",
		   "Set the architecture ID to that specified.");
   $usage.=sprintf("%-28s : %-55s\n","-noreturn","Pause after command execution rather than just exitting.");
   $usage.="\n";

   return $usage;
   }

#### End of SCRAM.pm ####
1;