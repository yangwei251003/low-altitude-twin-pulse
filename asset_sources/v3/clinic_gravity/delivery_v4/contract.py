"""Pure grouping contract; safe to import without Blender."""
GROUPS=('DeckStructure','CisternStructure','DeckDetails','CisternDetails','CisternWindow')
WORLD_PLACEMENT=(-9,6,-7)
def classify(name,group):
 if name=='DeckAssembly_VisibleUnion':return 'DeckStructure'
 if name=='CisternFrontWindow':return 'CisternWindow'
 if group in ('CisternShell','ProposedCover','ProposedOutlet'):return 'CisternStructure'
 if group in ('WindowAssembly','TankCornerProtection','TankSideFrame'):return 'CisternDetails'
 if group in ('DeckEdgeAssembly','DeckJointAssembly','PostConnections'):return 'DeckDetails'
 if group=='VisibleFasteners':
  if name.startswith('WindowFastener_'):return 'CisternDetails'
  if name.startswith(('DeckCornerBolt_','JointBolt_','SupportLeg_')):return 'DeckDetails'
 if group=='SurfaceHardware':
  if name=='LidInspectionJoint':return 'CisternDetails'
  if name.startswith('BearingNode_'):return 'DeckDetails'
 raise ValueError('Unclassified visible source object: '+name+' / '+str(group))
